import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/session.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// The Scolaris team: every school, its monthly subscription, the reminders sent to it, and the block. Late schools come first.
class AdminHome extends ConsumerWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(adminSchoolsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.schools), actions: [IconButton(tooltip: S.signOut, icon: const Icon(Icons.logout), onPressed: () => ref.read(sessionProvider.notifier).signOut())]),
      body: AsyncView<List<AdminSchool>>(
        value: list,
        onRetry: () => ref.invalidate(adminSchoolsProvider),
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.school_outlined, message: "Aucune école pour le moment."),
        data: (rows) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminSchoolsProvider);
            await ref.read(adminSchoolsProvider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(Space.md),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
            itemBuilder: (context, i) {
              final s = rows[i];
              final st = s.standing;
              return RowCard(
                leading: Avatar(s.name),
                title: s.name,
                subtitle: [if (s.city != null) s.city!, if (st != null && st.late) '${S.overdueMonths(st.overdueMonths)} · ${formatFcfa(st.remaining)}' else if (st == null) 'Sans abonnement', if (s.reminders > 0) '${s.reminders} rappel(s)'].join(' · '),
                trailing: s.blocked
                    ? const StatusBadge('Bloquée', tone: Tone.danger, icon: Icons.block)
                    : (st != null && st.late ? const StatusBadge(S.lateOnes, tone: Tone.warning, icon: Icons.error_outline) : const StatusBadge('À jour', tone: Tone.success, icon: Icons.check_circle_outline)),
                onTap: () => context.push('/admin/schools/${s.id}'),
              );
            },
          ),
        ),
      ),
    );
  }
}

class AdminSchoolPage extends ConsumerWidget {
  const AdminSchoolPage({super.key, required this.schoolId});
  final int schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(adminSchoolProvider(schoolId));
    void refresh() {
      ref.invalidate(adminSchoolProvider(schoolId));
      ref.invalidate(adminSchoolsProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(d.valueOrNull?.school.name ?? S.schools)),
      body: AsyncView<AdminSchoolDetail>(
        value: d,
        onRetry: refresh,
        data: (x) => RefreshIndicator(onRefresh: () async { refresh(); await ref.read(adminSchoolProvider(schoolId).future); }, child: _Detail(detail: x, refresh: refresh)),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.detail, required this.refresh});
  final AdminSchoolDetail detail;
  final VoidCallback refresh;

  Future<void> _do(BuildContext context, WidgetRef ref, Future<void> Function() action, String done, {bool stepUp = false}) async {
    try {
      if (stepUp) {
        final ok = await withStepUp<bool>(context, ref, () async { await action(); return true; });
        if (ok != true) return;
      } else {
        await action();
      }
      refresh();
      if (context.mounted) showMessage(context, done);
    } catch (e) {
      if (context.mounted) reportError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final repo = ref.read(repoProvider);
    final s = detail.school;
    final st = detail.standing;
    final id = s.id;
    return ListView(padding: const EdgeInsets.all(Space.md), children: [
      Row(children: [
        Expanded(child: Text(s.city ?? '', style: t.bodyMedium)),
        Flexible(child: s.blocked ? const StatusBadge('Accès suspendu', tone: Tone.danger, icon: Icons.block) : const StatusBadge('Accès actif', tone: Tone.success, icon: Icons.check_circle_outline)),
      ]),
      if (s.blocked && detail.blockedReason != null) Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text('Motif : ${detail.blockedReason}', style: t.bodySmall)),
      const SizedBox(height: Space.md),
      if (st == null) const InfoBanner(S.noSubscriptionYet) else _Standing(st),
      const SizedBox(height: Space.md),
      FilledButton.icon(onPressed: () => _subscription(context, ref, st), icon: const Icon(Icons.edit_calendar_outlined), label: const Text(S.setSubscription)),
      if (st != null) ...[
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(onPressed: () => _payment(context, ref), icon: const Icon(Icons.payments_outlined), label: const Text(S.recordPayment)),
        if (st.late && !s.blocked) ...[
          const SectionHeader('Relances et blocage'),
          Text('Rappels envoyés : ${detail.reminders} · Dernier avis : ${detail.finalNotices == 0 ? 'non' : (detail.lastFinalBlockOn == null ? 'oui' : 'oui, suspension le ${formatDate(detail.lastFinalBlockOn!)}')}', style: t.bodySmall),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: () async {
              if (await confirmDialog(context, title: S.sendReminder, message: 'Le directeur et la secrétaire verront ce rappel dans l\'application.', confirm: 'Envoyer') && context.mounted) {
                await _do(context, ref, () => repo.adminSendNotice(id, 'reminder'), 'Rappel envoyé.');
              }
            },
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text(S.sendReminder),
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(onPressed: () => _finalNotice(context, ref), icon: const Icon(Icons.warning_amber_outlined), label: const Text(S.sendFinal)),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Palette.danger, side: const BorderSide(color: Palette.danger)),
            onPressed: () => _block(context, ref),
            icon: const Icon(Icons.block),
            label: const Text(S.blockSchool),
          ),
        ],
        if (s.blocked) ...[
          const SizedBox(height: Space.sm),
          FilledButton.icon(
            onPressed: () async {
              if (await confirmDialog(context, title: S.unblockSchool, message: 'Le personnel et les parents retrouvent l\'accès.', confirm: S.unblockSchool) && context.mounted) {
                await _do(context, ref, () => repo.adminUnblock(id), 'Accès rétabli.', stepUp: true);
              }
            },
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text(S.unblockSchool),
          ),
        ],
      ],
      const SectionHeader(S.noticesHistory),
      if (detail.notices.isEmpty) const Text('Aucun avis envoyé.'),
      for (final n in detail.notices)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: RowCard(
            leading: Icon(n.kind == 'final_notice' || n.kind == 'blocked' ? Icons.warning_amber_outlined : Icons.notifications_none, color: n.kind == 'unblocked' ? Palette.success : Palette.body),
            title: '${S.noticeKind(n.kind)} · ${formatDate(n.createdAt)}',
            subtitle: '${n.title}${n.blockOn != null ? ' · suspension ${formatDate(n.blockOn!)}' : ''}',
            trailing: n.audience > 0 && (n.kind == 'reminder' || n.kind == 'final_notice') ? StatusBadge(S.seenBy(n.seenBy, n.audience), tone: n.seenBy == 0 ? Tone.warning : Tone.success, icon: Icons.visibility_outlined) : null,
          ),
        ),
      if (detail.payments.isNotEmpty) ...[
        const SectionHeader('Paiements reçus'),
        for (final p in detail.payments) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: RowCard(leading: const Icon(Icons.receipt_long_outlined, color: Palette.accent), title: '${formatFcfa(p.amount)} · ${S.methodLabel(p.method)}', subtitle: '${formatDate(p.paidOn)}${p.reference != null ? ' · ${p.reference}' : ''}')),
      ],
    ]);
  }

  Future<void> _subscription(BuildContext context, WidgetRef ref, Standing? st) async {
    final done = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _SubscriptionSheet(schoolId: detail.school.id, current: st));
    if (done == true) {
      refresh();
      if (context.mounted) showMessage(context, 'Abonnement enregistré.');
    }
  }

  Future<void> _payment(BuildContext context, WidgetRef ref) async {
    final done = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _PaymentSheet(schoolId: detail.school.id, suggested: detail.standing?.remaining ?? 0));
    if (done == true) {
      refresh();
      if (context.mounted) showMessage(context, 'Paiement enregistré.');
    }
  }

  Future<void> _finalNotice(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      helpText: S.blockOn,
      initialDate: now.add(const Duration(days: 10)),
      firstDate: now.add(const Duration(days: 7)),
      lastDate: now.add(const Duration(days: 90)),
      locale: const Locale('fr'),
    );
    if (date == null || !context.mounted) return;
    await _do(context, ref, () => ref.read(repoProvider).adminSendNotice(detail.school.id, 'final_notice', blockOn: date), 'Dernier avis envoyé.');
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final reason = await askText(context, title: S.blockSchool, label: S.blockReason, message: S.confirmBlock, confirm: S.blockSchool, danger: true, minLength: 3);
    if (reason == null || !context.mounted) return;
    await _do(context, ref, () => ref.read(repoProvider).adminBlock(detail.school.id, reason), 'École bloquée.', stepUp: true);
  }
}

class _Standing extends StatelessWidget {
  const _Standing(this.s);
  final Standing s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text('Mensualité · le ${s.billingDay} du mois', style: t.labelMedium)), Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatFcfa(s.monthlyAmount), style: t.titleSmall)))]),
          const SizedBox(height: Space.sm),
          Row(children: [
            Expanded(child: Text('Reste à payer', style: t.labelMedium)),
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatFcfa(s.remaining), style: t.headlineSmall?.copyWith(color: s.late ? Palette.danger : null)))),
          ]),
          const SizedBox(height: Space.sm),
          if (s.late) StatusBadge('${S.overdueMonths(s.overdueMonths)} · ${s.oldestLateDays} jours', tone: Tone.danger, icon: Icons.error_outline) else StatusBadge(s.remaining == 0 ? 'À jour' : 'Dans le délai de grâce', tone: Tone.success, icon: Icons.check_circle_outline),
          const SizedBox(height: Space.sm),
          Text('Facturé ${formatFcfa(s.billed)} · payé ${formatFcfa(s.paid)} · prochaine échéance ${formatDate(s.nextDue)}', style: t.bodySmall),
        ]),
      ),
    );
  }
}

class _SubscriptionSheet extends ConsumerStatefulWidget {
  const _SubscriptionSheet({required this.schoolId, this.current});
  final int schoolId;
  final Standing? current;

  @override
  ConsumerState<_SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends ConsumerState<_SubscriptionSheet> {
  late final _amount = TextEditingController(text: widget.current == null ? '' : formatFcfa(widget.current!.monthlyAmount, unit: false));
  late final _day = TextEditingController(text: '${widget.current?.billingDay ?? 5}');
  late final _grace = TextEditingController(text: '${widget.current?.graceDays ?? 5}');
  late DateTime _start = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _day.dispose();
    _grace.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseFcfa(_amount.text);
    final day = int.tryParse(_day.text);
    final grace = int.tryParse(_grace.text) ?? 5;
    if (amount == null || amount <= 0 || day == null || day < 1 || day > 28) {
      setState(() => _error = 'Indiquez un montant et un jour entre 1 et 28.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).adminSetSubscription(widget.schoolId, monthlyAmount: amount, billingDay: day, startedOn: _start, graceDays: grace);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(S.setSubscription, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.md),
          TextField(controller: _amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, FcfaInputFormatter()], decoration: const InputDecoration(labelText: S.monthlyAmount, suffixText: 'FCFA')),
          const SizedBox(height: Space.md),
          Row(children: [
            Expanded(child: TextField(controller: _day, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: S.billingDay))),
            const SizedBox(width: Space.md),
            Expanded(child: TextField(controller: _grace, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: S.graceDays))),
          ]),
          const SizedBox(height: Space.md),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2024), lastDate: DateTime(2035), locale: const Locale('fr'));
              if (d != null) setState(() => _start = d);
            },
            child: InputDecorator(decoration: const InputDecoration(labelText: S.startedOn, suffixIcon: Icon(Icons.calendar_today_outlined)), child: Text(formatDate(_start))),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
          const SizedBox(height: Space.lg),
          BusyButton(label: S.save, onPressed: _save, busy: _busy),
        ]),
      );
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.schoolId, required this.suggested});
  final int schoolId, suggested;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  late final _amount = TextEditingController(text: widget.suggested > 0 ? formatFcfa(widget.suggested, unit: false) : '');
  final _ref = TextEditingController();
  String _method = 'wave';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseFcfa(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Entrez un montant');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await withStepUp<bool>(context, ref, () async {
        await ref.read(repoProvider).adminRecordPayment(widget.schoolId, amount: amount, method: _method, reference: _ref.text);
        return true;
      });
      if (ok == true && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(S.recordPayment, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.md),
          TextField(controller: _amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, FcfaInputFormatter()], decoration: const InputDecoration(labelText: S.amount, suffixText: 'FCFA')),
          const SizedBox(height: Space.md),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final m in const ['wave', 'orange_money', 'mtn_momo', 'moov_money', 'virement', 'cheque', 'especes']) ChoiceChip(label: Text(S.methodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m))]),
          const SizedBox(height: Space.md),
          TextField(controller: _ref, decoration: const InputDecoration(labelText: S.reference)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
          const SizedBox(height: Space.lg),
          BusyButton(label: S.recordPayment, onPressed: _save, busy: _busy),
        ]),
      );
}
