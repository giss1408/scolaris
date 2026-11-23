import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

class ClassPage extends ConsumerWidget {
  const ClassPage({super.key, required this.classroomId, required this.name, required this.level});
  final int classroomId;
  final String name, level;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text(name),
            bottom: const TabBar(tabs: [Tab(text: S.evaluations), Tab(text: S.results), Tab(text: S.roll)]),
          ),
          body: TabBarView(children: [_Evaluations(classroomId: classroomId), _Results(classroomId: classroomId), _RollCall(classroomId: classroomId)]),
        ),
      );
}

// ---- evaluations ---------------------------------------------------------------------------------------------------------------------

class _Evaluations extends ConsumerWidget {
  const _Evaluations({required this.classroomId});
  final int classroomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evals = ref.watch(evaluationsProvider(classroomId));
    final subjects = ref.watch(subjectsProvider).valueOrNull ?? const <Subject>[];
    String subjectName(int id) => subjects.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? 'Matière';
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _NewEvaluationSheet(classroomId: classroomId)) == true) {
            ref.invalidate(evaluationsProvider(classroomId));
          }
        },
        icon: const Icon(Icons.add),
        label: const Text(S.newEvaluation),
      ),
      body: AsyncView<List<Evaluation>>(
        value: evals,
        onRetry: () => ref.invalidate(evaluationsProvider(classroomId)),
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.edit_note_outlined, message: S.noEvaluations),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
          itemBuilder: (context, i) {
            final e = list[i];
            return RowCard(
              leading: const Icon(Icons.edit_note_outlined, color: Palette.accent),
              title: '${subjectName(e.subjectId)} · ${S.kindEval(e.kind)}',
              subtitle: '${S.periodLabel(e.period)} · ${formatDate(e.heldOn)} · sur ${e.maxScore}${e.title != null ? ' · ${e.title}' : ''}',
              trailing: e.locked ? const StatusBadge(S.lockedBadge, tone: Tone.success, icon: Icons.lock_outline) : const Icon(Icons.chevron_right),
              onTap: () async {
                await context.push('/grades/evaluation/${e.id}');
                ref.invalidate(evaluationsProvider(classroomId));
                ref.invalidate(resultsProvider);
              },
            );
          },
        ),
      ),
    );
  }
}

class _NewEvaluationSheet extends ConsumerStatefulWidget {
  const _NewEvaluationSheet({required this.classroomId});
  final int classroomId;

  @override
  ConsumerState<_NewEvaluationSheet> createState() => _NewEvaluationSheetState();
}

class _NewEvaluationSheetState extends ConsumerState<_NewEvaluationSheet> {
  int? _subject;
  int _period = 1;
  String _kind = 'devoir';
  int _max = 20;
  final _title = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_subject == null) {
      setState(() => _error = 'Choisissez une matière');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).addEvaluation(classroomId: widget.classroomId, subjectId: _subject!, period: _period, kind: _kind, title: _title.text, maxScore: _max);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(classSubjectsProvider(widget.classroomId));
    final label = Theme.of(context).textTheme.labelMedium;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(S.newEvaluation, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Space.md),
        Text(S.subject, style: label),
        const SizedBox(height: Space.sm),
        subjects.when(
          loading: () => const SkeletonBox(height: 40),
          error: (e, _) => Text(userMessage(e)),
          data: (list) => list.isEmpty
              ? Text(ref.watch(meProvider).role == 'teacher' ? S.noSubjectForYou : S.noSubjects)
              : Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final s in list) ChoiceChip(label: Text(s.name), selected: _subject == s.id, onSelected: (_) => setState(() => _subject = s.id))]),
        ),
        const SizedBox(height: Space.md),
        Text(S.period, style: label),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, children: [for (final p in const [1, 2, 3]) ChoiceChip(label: Text(S.periodLabel(p)), selected: _period == p, onSelected: (_) => setState(() => _period = p))]),
        const SizedBox(height: Space.md),
        Text(S.kind, style: label),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, children: [for (final k in const ['devoir', 'interrogation', 'composition']) ChoiceChip(label: Text(S.kindEval(k)), selected: _kind == k, onSelected: (_) => setState(() => _kind = k))]),
        const SizedBox(height: Space.md),
        Text(S.outOf, style: label),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, children: [for (final m in const [20, 10]) ChoiceChip(label: Text('/ $m'), selected: _max == m, onSelected: (_) => setState(() => _max = m))]),
        const SizedBox(height: Space.md),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Titre (facultatif)')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
        const SizedBox(height: Space.lg),
        BusyButton(label: S.save, onPressed: _save, busy: _busy),
      ]),
    );
  }
}

// ---- results -------------------------------------------------------------------------------------------------------------------------

class _Results extends ConsumerStatefulWidget {
  const _Results({required this.classroomId});
  final int classroomId;

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  int _period = 1;

  @override
  Widget build(BuildContext context) {
    final key = (classroomId: widget.classroomId, period: _period);
    final res = ref.watch(resultsProvider(key));
    final t = Theme.of(context).textTheme;
    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(Space.md), children: [
          for (final p in const [1, 2, 3, 0]) Padding(padding: const EdgeInsets.only(right: Space.sm), child: ChoiceChip(label: Text(S.periodLabel(p)), selected: _period == p, onSelected: (_) => setState(() => _period = p))),
        ]),
      ),
      Expanded(
        child: AsyncView<ClassResults>(
          value: res,
          onRetry: () => ref.invalidate(resultsProvider(key)),
          isEmpty: (r) => r.rows.isEmpty,
          empty: const EmptyState(icon: Icons.groups_outlined, message: 'Aucun élève dans cette classe.'),
          data: (r) => ListView(padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xl), children: [
            if (r.classAverage != null) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: Text('Moyenne de la classe : ${r.classAverage}', style: t.titleSmall)),
            for (final row in [...r.rows]..sort((a, b) => (a.position ?? 999).compareTo(b.position ?? 999)))
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: RowCard(
                  leading: Avatar(row.name),
                  title: row.name,
                  subtitle: [row.rankLabel == '—' ? 'Pas encore classé(e)' : row.rankLabel, if (row.honour != null) S.honourLabel(row.honour!)].join(' · '),
                  trailing: row.average == null
                      ? const Text('—')
                      : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(row.average!, style: t.titleMedium?.copyWith(color: row.passes == false ? Palette.danger : Palette.ink)),
                          if (row.passes == false) const StatusBadge('< 10', tone: Tone.danger, icon: Icons.trending_down),
                        ]),
                  onTap: () => context.push('/grades/report/${row.enrollmentId}?period=$_period'),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

// ---- roll call -----------------------------------------------------------------------------------------------------------------------

class _RollCall extends ConsumerStatefulWidget {
  const _RollCall({required this.classroomId});
  final int classroomId;

  @override
  ConsumerState<_RollCall> createState() => _RollCallState();
}

class _RollCallState extends ConsumerState<_RollCall> {
  DateTime _day = DateTime.now();
  List<({int enrollmentId, String name})>? _students;
  final Map<int, String> _status = {}; // enrollmentId -> absence | retard (absent from the map = present)
  final Set<int> _justified = {};
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _students = null;
      _error = null;
      _status.clear();
      _justified.clear();
    });
    try {
      final repo = ref.read(repoProvider);
      final results = await repo.results(widget.classroomId, 1);
      final marked = await repo.absencesOfDay(widget.classroomId, _day);
      if (!mounted) return;
      setState(() {
        _students = [for (final r in results.rows) (enrollmentId: r.enrollmentId, name: r.name)];
        for (final m in marked) {
          _status[m.enrollmentId] = m.kind;
          if (m.justified) _justified.add(m.enrollmentId);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).recordAbsences(widget.classroomId, _day, [for (final e in _status.entries) (enrollmentId: e.key, kind: e.value, justified: _justified.contains(e.key))]);
      if (mounted) showMessage(context, 'Appel enregistré');
    } catch (e) {
      if (mounted) reportError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    final students = _students;
    if (students == null) return const SkeletonList();
    return Column(children: [
      ListTile(
        title: Text(formatDate(_day)),
        subtitle: Text('${_status.values.where((s) => s == 'absence').length} absent(s) · ${_status.values.where((s) => s == 'retard').length} en retard'),
        trailing: const Icon(Icons.calendar_today_outlined),
        onTap: () async {
          final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now(), locale: const Locale('fr'));
          if (d != null) {
            _day = d;
            _load();
          }
        },
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
          itemCount: students.length,
          separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
          itemBuilder: (context, i) {
            final s = students[i];
            final st = _status[s.enrollmentId];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Avatar(s.name, size: 32), const SizedBox(width: Space.sm), Expanded(child: Text(s.name, style: Theme.of(context).textTheme.titleSmall))]),
                  const SizedBox(height: Space.sm),
                  Wrap(spacing: Space.sm, children: [
                    ChoiceChip(label: const Text(S.markPresent), selected: st == null, onSelected: (_) => setState(() { _status.remove(s.enrollmentId); _justified.remove(s.enrollmentId); })),
                    ChoiceChip(label: const Text(S.absentLabel), selected: st == 'absence', onSelected: (_) => setState(() => _status[s.enrollmentId] = 'absence')),
                    ChoiceChip(label: const Text(S.late_), selected: st == 'retard', onSelected: (_) => setState(() => _status[s.enrollmentId] = 'retard')),
                    if (st != null) FilterChip(label: const Text('Justifié'), selected: _justified.contains(s.enrollmentId), onSelected: (v) => setState(() => v ? _justified.add(s.enrollmentId) : _justified.remove(s.enrollmentId))),
                  ]),
                ]),
              ),
            );
          },
        ),
      ),
      SafeArea(child: Padding(padding: const EdgeInsets.all(Space.md), child: BusyButton(label: S.saveRoll, onPressed: _save, busy: _busy))),
    ]);
  }
}
