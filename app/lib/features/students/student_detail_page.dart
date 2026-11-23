import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../money/pay_sheet.dart';

class StudentDetailPage extends ConsumerWidget {
  const StudentDetailPage({super.key, required this.studentId, required this.enrollmentId, required this.classroom});
  final int studentId, enrollmentId;
  final String classroom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (id: studentId, enrollmentId: enrollmentId, classroom: classroom);
    final student = ref.watch(studentProvider(key));
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.studentSheet)),
      body: AsyncView<StudentDetail>(
        value: student,
        onRetry: () => ref.invalidate(studentProvider(key)),
        data: (s) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(studentProvider(key));
            ref.invalidate(accountProvider(enrollmentId));
          },
          child: ListView(padding: const EdgeInsets.all(Space.md), children: [
            _Header(s),
            const SizedBox(height: Space.md),
            if (s.contacts.isNotEmpty) _QuickActions(s.contacts.firstWhere((c) => c.financial, orElse: () => s.contacts.first)),
            if (me.canCollect) ...[
              const SectionHeader(S.account),
              _AccountCard(enrollmentId: enrollmentId),
            ],
            const SectionHeader(S.contacts),
            if (s.contacts.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(Space.md), child: Text('Aucun contact enregistré.')))
            else
              Column(children: [for (final c in s.contacts) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: _ContactCard(c))]),
            if (s.siblings.isNotEmpty) ...[
              const SectionHeader('${S.family} (frères et sœurs)'),
              for (final sib in s.siblings) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: RowCard(leading: Avatar(sib.name), title: sib.name)),
            ],
            if (me.canCollect) ...[
              const SectionHeader(S.history),
              _History(enrollmentId: enrollmentId),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.s);
  final StudentDetail s;

  @override
  Widget build(BuildContext context) => Column(children: [
        ProfileHeader(
          name: s.name,
          subtitle: '${s.classroom} · N° ${s.internalNumber}',
          badge: Wrap(spacing: Space.sm, runSpacing: Space.xs, alignment: WrapAlignment.center, children: [
            StatusBadge(s.assigned ? S.assigned : S.notAssigned, tone: s.assigned ? Tone.info : Tone.neutral),
            StatusBadge(s.sex == 'F' ? S.female : S.male),
          ]),
          detail: [if (s.matricule != null) 'Matricule ${s.matricule}', if (s.birthDate != null) 'Né(e) le ${formatDate(s.birthDate!)}${s.birthPlace != null ? ' à ${s.birthPlace}' : ''}'].join(' · '),
        ),
      ]);
}

class _QuickActions extends StatelessWidget {
  const _QuickActions(this.c);
  final Contact c;

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showMessage(context, "Impossible d'ouvrir l'application.");
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () => _open(context, Uri(scheme: 'tel', path: c.phone)), icon: const Icon(Icons.call_outlined), label: const Text(S.call))),
        const SizedBox(width: Space.md),
        Expanded(child: OutlinedButton.icon(onPressed: () => _open(context, Uri.parse('https://wa.me/${c.phone.replaceAll('+', '')}')), icon: const Icon(Icons.chat_outlined), label: const Text(S.whatsapp))),
      ]);
}

class _ContactCard extends StatelessWidget {
  const _ContactCard(this.c);
  final Contact c;

  @override
  Widget build(BuildContext context) => RowCard(
        leading: Avatar(c.name),
        title: c.name,
        subtitle: '${S.relationLabel(c.relation)} · ${c.phone}',
        trailing: Wrap(spacing: 4, children: [
          if (c.financial) const Tooltip(message: S.financialResp, child: Icon(Icons.account_balance_wallet_outlined, size: 20, color: Palette.accent)),
          if (c.optin) const Tooltip(message: 'Accepte WhatsApp', child: Icon(Icons.mark_chat_read_outlined, size: 20, color: Palette.success)),
        ]),
      );
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.enrollmentId});
  final int enrollmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acc = ref.watch(accountProvider(enrollmentId));
    final me = ref.watch(meProvider);
    final t = Theme.of(context).textTheme;
    return acc.when(
      skipLoadingOnReload: true,
      loading: () => const SkeletonBox(height: 180, radius: Radii.md),
      error: (e, _) => SizedBox(height: 180, child: ErrorState(error: e, onRetry: () => ref.invalidate(accountProvider(enrollmentId)))),
      data: (d) {
        final a = d.account;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _Figure(S.total, formatFcfa(a.totalDue))),
                Expanded(child: _Figure(S.received, formatFcfa(a.credited))),
                Expanded(child: _Figure(S.remaining, formatFcfa(a.remaining), color: a.remaining == 0 ? Palette.success : null)),
              ]),
              const SizedBox(height: Space.md),
              if (a.lines.isEmpty) Text('Aucun frais défini pour cette classe.', style: t.bodyMedium),
              for (final l in a.lines) _LineRow(l),
              if (a.creditBalance > 0) Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text('Avance : ${formatFcfa(a.creditBalance)}', style: t.bodySmall)),
              const SizedBox(height: Space.md),
              if (me.canCollect) BusyButton(label: S.pay, onPressed: a.remaining == 0 && a.lines.isNotEmpty ? null : () => showPaySheet(context, ref, enrollmentId: enrollmentId, remaining: a.remaining)),
              if (me.isDirector && a.remaining > 0) TextButton.icon(onPressed: () => showDiscountSheet(context, ref, enrollmentId: enrollmentId, max: a.totalDue), icon: const Icon(Icons.percent_outlined), label: const Text(S.grantDiscount)),
            ]),
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color});
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: t.bodySmall),
      FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: t.titleSmall?.copyWith(color: color))),
    ]);
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow(this.l);
  final AccountLine l;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (label, tone, icon) = l.isPaid ? (S.paid, Tone.success, Icons.check_circle_outline) : l.lateDays > 0 ? (S.late, Tone.danger, Icons.error_outline) : (S.toPay, Tone.neutral, Icons.schedule_outlined);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${S.kindLabel(l.kind)} · ${l.label}', style: t.bodyMedium),
            Text('${formatFcfa(l.remaining == 0 ? l.amount : l.remaining)}${l.remaining == 0 ? '' : ' restants'} · avant le ${formatDate(l.dueDate)}', style: t.bodySmall),
          ]),
        ),
        StatusBadge(label, tone: tone, icon: icon),
      ]),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.enrollmentId});
  final int enrollmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acc = ref.watch(accountProvider(enrollmentId));
    return acc.maybeWhen(
      data: (d) => d.payments.isEmpty && d.discounts.isEmpty
          ? const Card(child: Padding(padding: EdgeInsets.all(Space.md), child: Text('Aucun paiement pour le moment.')))
          : Column(children: [
              for (final p in d.payments)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: RowCard(
                    leading: Icon(p.isCreditNote ? Icons.undo : Icons.receipt_long_outlined, color: p.isCreditNote ? Palette.danger : Palette.accent),
                    title: '${formatFcfa(p.amount)} · ${S.methodLabel(p.method)}',
                    subtitle: '${p.receipt} · ${formatDate(p.paidAt)}',
                    trailing: p.cancelled ? const StatusBadge(S.cancelledBadge, tone: Tone.danger, icon: Icons.block) : const Icon(Icons.chevron_right),
                    onTap: () => context.push('/receipt/${p.id}'),
                  ),
                ),
              for (final x in d.discounts)
                Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: RowCard(leading: const Icon(Icons.percent_outlined, color: Palette.accent), title: 'Réduction ${formatFcfa(x.amount)}', subtitle: '${x.kind} · ${x.reason}')),
            ]),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
