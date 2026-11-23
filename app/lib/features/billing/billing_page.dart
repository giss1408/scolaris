import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/school_logo.dart';
import '../../core/session.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// The line at the top of the app for the director and the secretary: a late subscription, a final notice with its date, or the block.
class BillingBannerBar extends StatelessWidget {
  const BillingBannerBar({super.key, required this.banner, required this.onTap});
  final BillingBanner banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (banner.level == 'info') return const SizedBox.shrink();
    final blocked = banner.level == 'blocked';
    final (bg, fg, icon) = switch (banner.level) {
      'blocked' => (const Color(0xFFFEE2E2), const Color(0xFF991B1B), Icons.block),
      'final' => (const Color(0xFFFEE2E2), const Color(0xFF991B1B), Icons.warning_amber_rounded),
      _ => (const Color(0xFFFEF3C7), const Color(0xFF92400E), Icons.info_outline),
    };
    final when = banner.blockOn == null ? '' : ' Suspension le ${formatDate(banner.blockOn!)}.';
    return Semantics(
      button: true,
      label: '${banner.title}. ${S.subscription}',
      child: Material(
        color: bg,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            child: Row(children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: Space.sm),
              Expanded(child: Text('${banner.title}.$when', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg))),
              Text(blocked ? S.subscription : 'Voir', style: TextStyle(fontSize: 13, color: fg, decoration: TextDecoration.underline)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// What the school owes the Scolaris team and the notices it received. Opening a notice marks it read (the team sees who read it).
class BillingPage extends ConsumerWidget {
  const BillingPage({super.key, this.embedded = false});

  /// Shown inside the "access suspended" screen instead of as its own page.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(billingProvider);
    final body = AsyncView<BillingInfo>(
      value: info,
      onRetry: () => ref.invalidate(billingProvider),
      data: (b) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(billingProvider);
          await ref.read(billingProvider.future);
        },
        child: ListView(padding: const EdgeInsets.all(Space.md), children: [
          if (b.standing == null)
            const Card(child: Padding(padding: EdgeInsets.all(Space.md), child: Text("Aucun abonnement n'est défini pour votre établissement.")))
          else
            _StandingCard(b.standing!),
          const SectionHeader(S.noticesHistory),
          if (b.notices.isEmpty) const Text('Aucun avis pour le moment.'),
          for (final n in b.notices) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: _NoticeCard(n)),
        ]),
      ),
    );
    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text(S.subscriptionTitle)), body: body);
  }
}

class _StandingCard extends StatelessWidget {
  const _StandingCard(this.s);
  final Standing s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Mensualité', style: t.labelMedium)),
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatFcfa(s.monthlyAmount), style: t.titleSmall))),
          ]),
          const SizedBox(height: Space.sm),
          Row(children: [
            Expanded(child: Text('Reste à payer', style: t.labelMedium)),
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatFcfa(s.remaining), style: t.headlineSmall?.copyWith(color: s.late ? Palette.danger : null)))),
          ]),
          const SizedBox(height: Space.sm),
          if (s.late) StatusBadge('${S.overdueMonths(s.overdueMonths)} · ${s.oldestLateDays} jours', tone: Tone.danger, icon: Icons.error_outline) else StatusBadge(s.remaining == 0 ? 'À jour' : 'Dans le délai', tone: Tone.success, icon: Icons.check_circle_outline),
          const SizedBox(height: Space.sm),
          Text('Prochaine échéance : ${formatDate(s.nextDue)}', style: t.bodySmall),
        ]),
      ),
    );
  }
}

class _NoticeCard extends ConsumerWidget {
  const _NoticeCard(this.n);
  final Notice n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final tone = switch (n.kind) { 'final_notice' || 'blocked' => Tone.danger, 'reminder' => Tone.warning, 'unblocked' => Tone.success, _ => Tone.info };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Wrap(spacing: Space.sm, children: [StatusBadge(S.noticeKind(n.kind), tone: tone), if (!n.seen) const StatusBadge('Nouveau', tone: Tone.info, icon: Icons.fiber_new_outlined)])),
            Text(formatDate(n.createdAt), style: t.bodySmall),
          ]),
          const SizedBox(height: Space.sm),
          Text(n.title, style: t.titleSmall),
          const SizedBox(height: Space.xs),
          Text(n.text, style: t.bodyMedium),
          if (n.blockOn != null) Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text('Suspension annoncée : ${formatDate(n.blockOn!)}', style: t.titleSmall?.copyWith(color: Palette.danger))),
          if (!n.seen)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await ref.read(repoProvider).markNoticeSeen(n.id);
                  ref.invalidate(billingProvider);
                  await ref.read(sessionProvider.notifier).refreshProfile();
                },
                icon: const Icon(Icons.done_all),
                label: const Text(S.markRead),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The only screen a blocked school's director and secretary get: why, what is owed, and the notices. Everyone else just sees the message.
class BlockedPage extends ConsumerWidget {
  const BlockedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.accessSuspended), actions: [IconButton(tooltip: S.signOut, icon: const Icon(Icons.logout), onPressed: () => ref.read(sessionProvider.notifier).signOut())]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(children: [
            SchoolLogo(name: me.schoolName, version: me.logoVersion, size: 48),
            const SizedBox(width: Space.md),
            Expanded(child: Text(me.schoolName, style: Theme.of(context).textTheme.titleMedium)),
          ]),
        ),
        const InfoBanner(S.accessSuspendedText, icon: Icons.block),
        const Expanded(child: BillingPage(embedded: true)),
      ]),
    );
  }
}
