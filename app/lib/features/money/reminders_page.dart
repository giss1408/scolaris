import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// The reminders due today. A person sends each message from the school's WhatsApp (prepared link), then marks it sent.
/// Nothing touches the pupil from here: the last step ("à la direction") only informs the director.
class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(remindersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.reminders)),
      body: AsyncView<List<ReminderItem>>(
        value: items,
        onRetry: () => ref.invalidate(remindersProvider),
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.mark_chat_read_outlined, message: S.noReminders),
        data: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(remindersProvider);
            await ref.read(remindersProvider.future);
          },
          child: ListView(padding: const EdgeInsets.all(Space.md), children: [
            if (list.any((i) => !i.canSendNow && i.channel != 'direction')) const Padding(padding: EdgeInsets.only(bottom: Space.md), child: InfoBanner(S.outsideHours, icon: Icons.schedule_outlined)),
            for (final i in list) Padding(padding: const EdgeInsets.only(bottom: Space.md), child: _ReminderCard(i)),
          ]),
        ),
      ),
    );
  }
}

class _ReminderCard extends ConsumerWidget {
  const _ReminderCard(this.i);
  final ReminderItem i;

  Future<void> _done(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(remindersProvider);
    } catch (e) {
      if (context.mounted) reportError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final repo = ref.read(repoProvider);
    final direction = i.channel == 'direction';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(i.familyName),
            const SizedBox(width: Space.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(i.familyName, style: t.titleSmall), Text(i.contactName ?? 'Aucun contact', style: t.bodySmall)])),
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatFcfa(i.amount), style: t.titleSmall?.copyWith(color: Palette.danger)))),
          ]),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
            StatusBadge(S.stepLabel(i.step), tone: direction ? Tone.warning : Tone.info, icon: direction ? Icons.account_balance_outlined : Icons.notifications_none),
            StatusBadge(switch (i.channel) { 'whatsapp' => 'WhatsApp', 'sms' => 'SMS', 'direction' => 'Direction', _ => 'À appeler' }, icon: i.channel == 'appel' ? Icons.call_outlined : Icons.chat_outlined),
          ]),
          const SizedBox(height: Space.md),
          Container(padding: const EdgeInsets.all(Space.md), decoration: BoxDecoration(color: Palette.page, borderRadius: BorderRadius.circular(Radii.sm)), child: Text(i.text, style: t.bodyMedium)),
          const SizedBox(height: Space.md),
          if (i.waLink != null)
            FilledButton.icon(
              onPressed: () async {
                final ok = await launchUrl(Uri.parse(i.waLink!), mode: LaunchMode.externalApplication);
                if (!context.mounted) return;
                if (!ok) {
                  showMessage(context, "Impossible d'ouvrir WhatsApp.");
                  return;
                }
                if (await confirmDialog(context, title: S.sentAsk, message: i.familyName, confirm: 'Oui, envoyé') && context.mounted) {
                  await _done(context, ref, () => repo.markReminderSent(i.id));
                }
              },
              icon: const Icon(Icons.chat_outlined),
              label: const Text(S.sendWhatsapp),
            )
          else if (i.phone != null && !direction)
            FilledButton.icon(onPressed: () => launchUrl(Uri(scheme: 'tel', path: i.phone), mode: LaunchMode.externalApplication), icon: const Icon(Icons.call_outlined), label: const Text(S.call)),
          const SizedBox(height: Space.sm),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: i.text)); if (context.mounted) showMessage(context, 'Message copié'); }, child: const Text('Copier'))),
            const SizedBox(width: Space.sm),
            Expanded(child: OutlinedButton(onPressed: () => _done(context, ref, () => repo.markReminderSent(i.id)), child: const Text(S.markSent))),
          ]),
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TextButton(onPressed: () => _done(context, ref, () => repo.skipReminder(i.id)), child: const Text(S.skip)),
            if (!direction) TextButton.icon(onPressed: () => _promise(context, ref), icon: const Icon(Icons.handshake_outlined), label: const Text(S.promise)),
          ]),
        ]),
      ),
    );
  }

  Future<void> _promise(BuildContext context, WidgetRef ref) async {
    final done = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _PromiseSheet(i));
    if (done == true) {
      ref.invalidate(remindersProvider);
      if (context.mounted) showMessage(context, 'Promesse enregistrée : pas de relance avant la date.');
    }
  }
}

class _PromiseSheet extends ConsumerStatefulWidget {
  const _PromiseSheet(this.i);
  final ReminderItem i;

  @override
  ConsumerState<_PromiseSheet> createState() => _PromiseSheetState();
}

class _PromiseSheetState extends ConsumerState<_PromiseSheet> {
  late final _amount = TextEditingController(text: formatFcfa(widget.i.amount, unit: false));
  DateTime? _date;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseFcfa(_amount.text);
    if (amount == null || amount <= 0 || _date == null) {
      setState(() => _error = 'Indiquez le montant et la date promise.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).recordPromise(widget.i.familyId, amount: amount, promisedFor: _date!);
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
          Text(S.promise, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.sm),
          Text(widget.i.familyName, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: Space.md),
          TextField(controller: _amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, FcfaInputFormatter()], decoration: const InputDecoration(labelText: S.amount, suffixText: 'FCFA')),
          const SizedBox(height: Space.md),
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, initialDate: now.add(const Duration(days: 7)), firstDate: now, lastDate: now.add(const Duration(days: 120)), locale: const Locale('fr'));
              if (d != null) setState(() => _date = d);
            },
            child: InputDecorator(decoration: const InputDecoration(labelText: 'Date promise', suffixIcon: Icon(Icons.calendar_today_outlined)), child: Text(_date == null ? 'Choisir' : formatDate(_date!))),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
          const SizedBox(height: Space.lg),
          BusyButton(label: S.save, onPressed: _save, busy: _busy),
        ]),
      );
}
