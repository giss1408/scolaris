import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

const _needsReference = {'wave', 'orange_money', 'mtn_momo', 'moov_money', 'virement', 'cheque'};
const _methodIcons = {
  'especes': Icons.payments_outlined,
  'wave': Icons.waves_outlined,
  'orange_money': Icons.phone_android_outlined,
  'mtn_momo': Icons.phone_android_outlined,
  'moov_money': Icons.phone_android_outlined,
  'virement': Icons.account_balance_outlined,
  'cheque': Icons.edit_note_outlined,
};

Future<void> showPaySheet(BuildContext context, WidgetRef ref, {required int enrollmentId, required int remaining}) async {
  await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _PaySheet(enrollmentId: enrollmentId, remaining: remaining));
}

class _PaySheet extends ConsumerStatefulWidget {
  const _PaySheet({required this.enrollmentId, required this.remaining});
  final int enrollmentId, remaining;

  @override
  ConsumerState<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends ConsumerState<_PaySheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.remaining > 0 ? formatFcfa(widget.remaining, unit: false) : '');
  final _reference = TextEditingController();
  String _method = 'especes';
  bool _busy = false;
  String? _error;
  // One key per opened sheet: a retry after a timeout sends the same key, so the server records the payment once.
  final _key = newIdempotencyKey();

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final amount = parseFcfa(_amount.text)!;
    final ok = await confirmDialog(context, title: S.pay, message: '${formatFcfa(amount)} · ${S.methodLabel(_method)}', confirm: S.pay);
    if (!ok) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await ref.read(repoProvider).pay(widget.enrollmentId, amount: amount, method: _method, reference: _reference.text, idempotencyKey: _key);
      HapticFeedback.lightImpact();
      ref.invalidate(accountProvider(widget.enrollmentId));
      ref.invalidate(dashboardProvider);
      ref.invalidate(arrearsProvider);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.push('/receipt/${p.id}?new=1');
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final methods = me.methods.isEmpty ? _methodIcons.keys.toList() : me.methods;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(S.pay, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _amount,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, FcfaInputFormatter()],
            decoration: const InputDecoration(labelText: S.amount, suffixText: 'FCFA'),
            validator: (v) {
              final n = parseFcfa(v ?? '');
              return n == null || n <= 0 ? 'Entrez un montant' : null;
            },
          ),
          const SizedBox(height: Space.md),
          Text(S.method, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final m in methods)
              ChoiceChip(
                avatar: Icon(_methodIcons[m] ?? Icons.payments_outlined, size: 18),
                label: Text(S.methodLabel(m)),
                selected: _method == m,
                onSelected: (_) => setState(() => _method = m),
              ),
          ]),
          if (_needsReference.contains(_method)) ...[
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _reference,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: S.reference, helperText: S.referenceHelp),
              validator: (v) => (v ?? '').trim().isEmpty ? S.required : null,
            ),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
          const SizedBox(height: Space.lg),
          BusyButton(label: S.pay, onPressed: _submit, busy: _busy),
        ]),
      ),
    );
  }
}

Future<void> showDiscountSheet(BuildContext context, WidgetRef ref, {required int enrollmentId, required int max}) async {
  await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _DiscountSheet(enrollmentId: enrollmentId, max: max));
}

class _DiscountSheet extends ConsumerStatefulWidget {
  const _DiscountSheet({required this.enrollmentId, required this.max});
  final int enrollmentId, max;

  @override
  ConsumerState<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends ConsumerState<_DiscountSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _kind = 'fratrie';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final amount = parseFcfa(_amount.text)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await withStepUp(context, ref, () => ref.read(repoProvider).grantDiscount(widget.enrollmentId, kind: _kind, amount: amount, reason: _reason.text));
      ref.invalidate(accountProvider(widget.enrollmentId));
      ref.invalidate(dashboardProvider);
      ref.invalidate(arrearsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(S.grantDiscount, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.md),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (final (k, label) in const [('fratrie', 'Fratrie'), ('personnel', 'Enfant du personnel'), ('bourse', 'Bourse'), ('exceptionnelle', 'Exceptionnelle')])
                ChoiceChip(label: Text(label), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
            ]),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, FcfaInputFormatter()],
              decoration: const InputDecoration(labelText: S.amount, suffixText: 'FCFA'),
              validator: (v) {
                final n = parseFcfa(v ?? '');
                if (n == null || n <= 0) return 'Entrez un montant';
                return n > widget.max ? 'Au plus ${formatFcfa(widget.max)}' : null;
              },
            ),
            const SizedBox(height: Space.md),
            TextFormField(controller: _reason, decoration: const InputDecoration(labelText: S.discountReason), validator: (v) => (v ?? '').trim().length < 3 ? S.required : null),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
            const SizedBox(height: Space.lg),
            BusyButton(label: S.save, onPressed: _submit, busy: _busy),
          ]),
        ),
      );
}
