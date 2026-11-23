import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Who teaches what in one class, and who is its head teacher. A teacher only reaches the classes (and subjects) listed here.
class ClassTeachersPage extends ConsumerStatefulWidget {
  const ClassTeachersPage({super.key, required this.classroomId, required this.name});
  final int classroomId;
  final String name;

  @override
  ConsumerState<ClassTeachersPage> createState() => _ClassTeachersPageState();
}

class _ClassTeachersPageState extends ConsumerState<ClassTeachersPage> {
  int? _head;
  List<({int staffId, int? subjectId})>? _assignments;
  bool _dirty = false;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final c = await ref.read(repoProvider).classTeachers(widget.classroomId);
      if (mounted) {
        setState(() {
          _head = c.headTeacherId;
          _assignments = [for (final a in c.assignments) (staffId: a.staffId, subjectId: a.subjectId)];
          _dirty = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).saveClassTeachers(widget.classroomId, headTeacherId: _head, assignments: _assignments!);
      ref.invalidate(classroomsProvider);
      if (mounted) {
        setState(() => _dirty = false);
        showMessage(context, S.assignmentsSaved);
      }
    } catch (e) {
      if (mounted) reportError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(List<StaffRow> teachers, List<Subject> subjects) async {
    final picked = await showModalBottomSheet<({int staffId, int? subjectId})>(context: context, isScrollControlled: true, builder: (_) => _AddAssignmentSheet(teachers: teachers, subjects: subjects));
    if (picked != null && !_assignments!.contains(picked)) {
      setState(() {
        _assignments = [..._assignments!, picked];
        _dirty = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffProvider);
    final subjects = ref.watch(subjectsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('${S.classTeachers} · ${widget.name}')),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : _assignments == null || staff.isLoading || subjects.isLoading
              ? const SkeletonList(rows: 3)
              : Builder(builder: (context) {
                  final teachers = (staff.valueOrNull ?? const <StaffRow>[]).where((s) => s.role == 'teacher' && s.active).toList();
                  final subs = subjects.valueOrNull ?? const <Subject>[];
                  String teacherName(int id) => teachers.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? 'Enseignant retiré';
                  String subjectName(int? id) => id == null ? S.allSubjects : (subs.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? 'Matière');
                  if (teachers.isEmpty) return const EmptyState(icon: Icons.group_outlined, message: S.noTeachers);
                  return ListView(padding: const EdgeInsets.all(Space.md), children: [
                    Text(S.headTeacher, style: t.labelMedium),
                    const SizedBox(height: Space.sm),
                    Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                      ChoiceChip(label: const Text('Aucun'), selected: _head == null, onSelected: (_) => setState(() { _head = null; _dirty = true; })),
                      for (final s in teachers) ChoiceChip(avatar: const Icon(Icons.star_outline, size: 16), label: Text(s.name), selected: _head == s.id, onSelected: (_) => setState(() { _head = s.id; _dirty = true; })),
                    ]),
                    const SizedBox(height: Space.xs),
                    Text('Le professeur principal voit toute la classe et écrit la conduite et les appréciations.', style: t.bodySmall),
                    const SectionHeader(S.classTeachers),
                    if (_assignments!.isEmpty) const Padding(padding: EdgeInsets.only(bottom: Space.sm), child: Text(S.noAssignments)),
                    for (final a in _assignments!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: RowCard(
                          leading: Avatar(teacherName(a.staffId)),
                          title: teacherName(a.staffId),
                          subtitle: subjectName(a.subjectId),
                          trailing: IconButton(tooltip: S.remove, icon: const Icon(Icons.delete_outline), onPressed: () => setState(() { _assignments = [..._assignments!]..remove(a); _dirty = true; })),
                        ),
                      ),
                    OutlinedButton.icon(onPressed: () => _add(teachers, subs), icon: const Icon(Icons.add), label: const Text(S.assignTeacher)),
                  ]);
                }),
      bottomNavigationBar: _dirty ? SafeArea(child: Padding(padding: const EdgeInsets.all(Space.md), child: BusyButton(label: S.save, onPressed: _save, busy: _busy))) : null,
    );
  }
}

class _AddAssignmentSheet extends StatefulWidget {
  const _AddAssignmentSheet({required this.teachers, required this.subjects});
  final List<StaffRow> teachers;
  final List<Subject> subjects;

  @override
  State<_AddAssignmentSheet> createState() => _AddAssignmentSheetState();
}

class _AddAssignmentSheetState extends State<_AddAssignmentSheet> {
  int? _teacher;
  int? _subject; // null = all subjects
  bool _all = false;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(S.assignTeacher, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.md),
          Text('Enseignant', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final s in widget.teachers) ChoiceChip(label: Text(s.name), selected: _teacher == s.id, onSelected: (_) => setState(() => _teacher = s.id))]),
          const SizedBox(height: Space.md),
          Text(S.subject, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            ChoiceChip(label: const Text(S.allSubjects), selected: _all, onSelected: (_) => setState(() { _all = true; _subject = null; })),
            for (final s in widget.subjects) ChoiceChip(label: Text(s.name), selected: !_all && _subject == s.id, onSelected: (_) => setState(() { _all = false; _subject = s.id; })),
          ]),
          const SizedBox(height: Space.lg),
          FilledButton(onPressed: _teacher == null || (!_all && _subject == null) ? null : () => Navigator.pop(context, (staffId: _teacher!, subjectId: _all ? null : _subject)), child: const Text(S.assignTeacher)),
        ]),
      );
}
