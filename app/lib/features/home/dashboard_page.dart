import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'shell_page.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key, required this.goTo});
  final void Function(int) goTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final dash = ref.watch(dashboardProvider);
    final arrears = ref.watch(arrearsProvider);
    final t = Theme.of(context).textTheme;
    Future<void> refresh() async {
      ref.invalidate(dashboardProvider);
      ref.invalidate(arrearsProvider);
      await ref.read(dashboardProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(S.hello(me.name.split(' ').first)),
        actions: [if (me.yearLabel != null) Padding(padding: const EdgeInsets.only(right: Space.md), child: Center(child: StatusBadge(me.yearLabel!, tone: Tone.info, icon: Icons.event_outlined)))],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(padding: const EdgeInsets.all(Space.md), children: [
          Text(me.schoolName, style: t.bodyMedium?.copyWith(color: Palette.body)),
          const SizedBox(height: Space.md),
          dash.when(
            skipLoadingOnReload: true,
            loading: () => const _StatsSkeleton(),
            error: (e, _) => SizedBox(height: 240, child: ErrorState(error: e, onRetry: () => ref.invalidate(dashboardProvider))),
            data: (d) => _Stats(d),
          ),
          const SizedBox(height: Space.md),
          Row(children: [
            if (me.canCollect) Expanded(child: FilledButton.icon(onPressed: () => goTo(tabIndexOf(true, S.tabStudents)), icon: const Icon(Icons.payments_outlined), label: const Text(S.pay))),
            if (me.canCollect && me.canEnrol) const SizedBox(width: Space.md),
            if (me.canEnrol) Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/students/new'), icon: const Icon(Icons.person_add_alt_outlined), label: const Text(S.newStudent))),
          ]),
          SectionHeader(S.toHandle, action: S.seeAll, onAction: () => goTo(tabIndexOf(true, S.tabArrears))),
          arrears.when(
            skipLoadingOnReload: true,
            loading: () => const Column(children: [SkeletonBox(height: 64, radius: Radii.md), SizedBox(height: Space.sm), SkeletonBox(height: 64, radius: Radii.md)]),
            error: (e, _) => SizedBox(height: 160, child: ErrorState(error: e, onRetry: () => ref.invalidate(arrearsProvider))),
            data: (rows) => rows.isEmpty
                ? const SizedBox(height: 140, child: EmptyState(icon: Icons.check_circle_outline, message: S.noArrears))
                : Column(children: [
                    for (final f in rows.take(3)) ...[
                      RowCard(
                        leading: Avatar(f.name),
                        title: f.name,
                        subtitle: '${S.children(f.children.length)} · ${S.lateDays(f.oldestLateDays)}',
                        trailing: Text(formatFcfa(f.total), style: t.titleSmall?.copyWith(color: Palette.danger)),
                        onTap: () => goTo(tabIndexOf(true, S.tabArrears)),
                      ),
                      const SizedBox(height: Space.sm),
                    ],
                  ]),
          ),
        ]),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats(this.d);
  final Dashboard d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: StatCard(label: S.collectedToday, value: formatFcfa(d.today), icon: Icons.today_outlined)),
        const SizedBox(width: Space.md),
        Expanded(child: StatCard(label: S.collectedMonth, value: formatFcfa(d.month), icon: Icons.calendar_month_outlined)),
      ]),
      const SizedBox(height: Space.md),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: StatCard(label: S.remaining, value: formatFcfa(d.remaining), icon: Icons.hourglass_bottom_outlined)),
        const SizedBox(width: Space.md),
        Expanded(child: StatCard(label: S.overdue, value: formatFcfa(d.overdue), icon: Icons.warning_amber_outlined, hint: d.overdue > 0 ? 'À relancer' : 'Rien en retard')),
      ]),
      const SizedBox(height: Space.md),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(S.recovery, style: t.labelMedium)), Text('${d.recoveryPct} %', style: t.titleMedium)]),
            const SizedBox(height: Space.sm),
            Semantics(
              label: '${S.recovery} ${d.recoveryPct} pour cent',
              child: ClipRRect(borderRadius: BorderRadius.circular(Radii.pill), child: LinearProgressIndicator(value: d.recoveryPct / 100, minHeight: 10, backgroundColor: Palette.line, color: Palette.accent)),
            ),
            const SizedBox(height: Space.sm),
            Text('${d.students} élèves · ${formatFcfa(d.year)} encaissés sur ${formatFcfa(d.expected)}', style: t.bodySmall),
          ]),
        ),
      ),
    ]);
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) => const Column(children: [
        Row(children: [Expanded(child: SkeletonBox(height: 92, radius: Radii.md)), SizedBox(width: Space.md), Expanded(child: SkeletonBox(height: 92, radius: Radii.md))]),
        SizedBox(height: Space.md),
        Row(children: [Expanded(child: SkeletonBox(height: 92, radius: Radii.md)), SizedBox(width: Space.md), Expanded(child: SkeletonBox(height: 92, radius: Radii.md))]),
        SizedBox(height: Space.md),
        SkeletonBox(height: 96, radius: Radii.md),
      ]);
}
