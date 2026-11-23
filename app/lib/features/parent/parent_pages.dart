import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/sensitive.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/school_logo.dart';
import '../../core/session.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'report_sheet.dart';

/// The parent space: her children (in any school that has her number), balance, report cards, receipts, absences. Read-only.
class ParentShell extends ConsumerStatefulWidget {
  const ParentShell({super.key});

  @override
  ConsumerState<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends ConsumerState<ParentShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _i, children: const [ChildrenPage(), _ParentProfile()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (i) => setState(() => _i = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.family_restroom_outlined), selectedIcon: Icon(Icons.family_restroom), label: S.myChildren),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: S.tabProfile),
          ],
        ),
      );
}

class ChildrenPage extends ConsumerWidget {
  const ChildrenPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kids = ref.watch(childrenProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.myChildren)),
      body: AsyncView<List<ChildRow>>(
        value: kids,
        onRetry: () => ref.invalidate(childrenProvider),
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.family_restroom_outlined, message: S.noChildren),
        data: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(childrenProvider);
            await ref.read(childrenProvider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(Space.md),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: Space.md),
            itemBuilder: (context, i) => _ChildCard(list[i]),
          ),
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard(this.c);
  final ChildRow c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final late = c.overdue > 0;
    if (c.blocked) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SchoolLogo(name: c.school, version: c.logoVersion, parentSchoolId: c.schoolId, size: 48),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: t.titleMedium),
                Text('${c.classroom} · ${c.school}', style: t.bodySmall),
                const SizedBox(height: Space.sm),
                const StatusBadge(S.serviceSuspended, tone: Tone.warning, icon: Icons.pause_circle_outline),
                const SizedBox(height: Space.xs),
                Text(S.contactSchool, style: t.bodySmall),
              ]),
            ),
          ]),
        ),
      );
    }
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => context.push('/parent/child/${c.enrollmentId}?name=${Uri.encodeComponent(c.name)}'),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              c.hasLogo ? SchoolLogo(name: c.school, version: c.logoVersion, parentSchoolId: c.schoolId, size: 48) : Avatar(c.name, size: 48),
              const SizedBox(width: Space.md),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.name, style: t.titleMedium), Text('${c.classroom} · ${c.school}', style: t.bodySmall)])),
              const Icon(Icons.chevron_right),
            ]),
            const SizedBox(height: Space.md),
            Row(children: [
              Expanded(child: Text('Reste à payer', style: t.labelMedium)),
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatFcfa(c.remaining), style: t.titleMedium))),
            ]),
            const SizedBox(height: Space.sm),
            if (late) StatusBadge('${formatFcfa(c.overdue)} en retard', tone: Tone.danger, icon: Icons.error_outline) else StatusBadge(c.remaining == 0 ? 'Tout est réglé' : 'À jour', tone: Tone.success, icon: Icons.check_circle_outline),
          ]),
        ),
      ),
    );
  }
}

class ChildPage extends ConsumerStatefulWidget {
  const ChildPage({super.key, required this.enrollmentId, required this.name});
  final int enrollmentId;
  final String name;

  @override
  ConsumerState<ChildPage> createState() => _ChildPageState();
}

class _ChildPageState extends ConsumerState<ChildPage> {
  int _period = 1;
  List<PaymentRow>? _payments;
  List<AbsenceRow>? _absences;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final repo = ref.read(repoProvider);
      final p = await repo.childPayments(widget.enrollmentId);
      final a = await repo.childAbsences(widget.enrollmentId);
      if (mounted) {
        setState(() {
          _payments = p;
          _absences = a;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : _payments == null
              ? const SkeletonList(rows: 3)
              : ListView(padding: const EdgeInsets.all(Space.md), children: [
                  FilledButton.icon(
                    onPressed: () async {
                      if (await showReportSheet(context, enrollmentId: widget.enrollmentId, childName: widget.name) && context.mounted) showMessage(context, S.reportSent);
                    },
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text(S.reportAbsence),
                  ),
                  const SizedBox(height: Space.sm),
                  OutlinedButton.icon(onPressed: () => context.push('/parent/child/${widget.enrollmentId}/timetable?name=${Uri.encodeComponent(widget.name)}'), icon: const Icon(Icons.calendar_view_week_outlined), label: const Text(S.timetable)),
                  _Reports(enrollmentId: widget.enrollmentId),
                  const SectionHeader(S.reportCard),
                  Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final p in const [1, 2, 3, 0]) ChoiceChip(label: Text(S.periodLabel(p)), selected: _period == p, onSelected: (_) => setState(() => _period = p))]),
                  const SizedBox(height: Space.sm),
                  FilledButton.icon(onPressed: () => context.push('/parent/report/${widget.enrollmentId}?period=$_period'), icon: const Icon(Icons.description_outlined), label: Text('Voir le bulletin · ${S.periodLabel(_period)}')),
                  const SectionHeader(S.payments),
                  const InfoBanner(S.payAtSchool, icon: Icons.info_outline),
                  const SizedBox(height: Space.sm),
                  if (_payments!.isEmpty) const Text(S.nothingYet),
                  for (final p in _payments!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: RowCard(
                        leading: Icon(p.isCreditNote ? Icons.undo : Icons.receipt_long_outlined, color: p.isCreditNote ? Palette.danger : Palette.accent),
                        title: '${formatFcfa(p.amount)} · ${S.methodLabel(p.method)}',
                        subtitle: '${p.receipt} · ${formatDate(p.paidAt)}',
                      ),
                    ),
                  const SectionHeader(S.absences),
                  if (_absences!.isEmpty) const Text(S.nothingYet),
                  for (final a in _absences!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: RowCard(
                        leading: Icon(a.kind == 'retard' ? Icons.schedule_outlined : Icons.event_busy_outlined),
                        title: '${a.kind == 'retard' ? 'Retard' : 'Absence'} · ${formatDate(a.day)}',
                        subtitle: a.course != null ? '${S.atCourse} : ${a.course!.subject} (${a.course!.start}-${a.course!.end})' : a.reason,
                        trailing: StatusBadge(a.justified ? 'Justifiée' : 'Non justifiée', tone: a.justified ? Tone.success : Tone.warning, icon: a.justified ? Icons.check : Icons.warning_amber),
                      ),
                    ),
                  const SizedBox(height: Space.lg),
                  Text('Les montants et les notes sont ceux enregistrés par l\'école.', style: t.bodySmall),
                ]),
    );
  }
}

/// The absences the parent has reported (recent and coming), each can be withdrawn.
class _Reports extends ConsumerWidget {
  const _Reports({required this.enrollmentId});
  final int enrollmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = enrollmentId;
    final list = ref.watch(childReportsProvider(id)).valueOrNull ?? const <AbsenceReport>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final today = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader(S.reportedAbsences),
      for (final r in list)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: RowCard(
            leading: const Icon(Icons.edit_calendar_outlined, color: Palette.accent),
            title: '${S.dayLong(r.day.weekday)} ${formatDate(r.day)}',
            subtitle: [S.reportReason(r.reason), if (r.note != null) r.note!].join(' · '),
            trailing: !r.day.isBefore(DateTime(today.year, today.month, today.day))
                ? TextButton(
                    onPressed: () async {
                      try {
                        await ref.read(repoProvider).withdrawAbsenceReport(id, r.day);
                        ref.invalidate(childReportsProvider(id));
                      } catch (e) {
                        if (context.mounted) reportError(context, e);
                      }
                    },
                    child: const Text(S.withdraw),
                  )
                : null,
          ),
        ),
    ]);
  }
}

class _ParentProfile extends ConsumerWidget {
  const _ParentProfile();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text(S.tabProfile)),
        body: ListView(padding: const EdgeInsets.all(Space.md), children: [
          const SizedBox(height: Space.sm),
          const ProfileHeader(name: 'Parent', subtitle: 'Espace des familles', badge: StatusBadge('Parent', tone: Tone.info, icon: Icons.family_restroom_outlined)),
          SettingsGroup(title: S.application, children: [
            const SettingsRow(icon: Icons.info_outline, label: 'Version', value: Config.version),
            SettingsRow(
              icon: Icons.logout,
              label: S.signOut,
              danger: true,
              onTap: () async {
                if (await confirmDialog(context, title: S.signOut, message: S.signOutAsk, confirm: S.signOut, danger: true)) {
                  await ref.read(sessionProvider.notifier).signOut();
                }
              },
            ),
          ]),
        ]),
      );
}
