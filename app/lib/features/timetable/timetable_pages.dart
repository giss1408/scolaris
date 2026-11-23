import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'week_view.dart';

/// The class's timetable (tab of the class page). The director and the secretary edit it; a teacher only reads it.
class ClassTimetableTab extends ConsumerWidget {
  const ClassTimetableTab({super.key, required this.classroomId});
  final int classroomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = ref.watch(classTimetableProvider(classroomId));
    return AsyncView<ClassTimetable>(
      value: tt,
      onRetry: () => ref.invalidate(classTimetableProvider(classroomId)),
      data: (data) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: data.editable
            ? FloatingActionButton.extended(
                onPressed: () async {
                  if (await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _SlotSheet(classroomId: classroomId, teachers: data.teachers)) == true) {
                    ref.invalidate(classTimetableProvider(classroomId));
                    if (context.mounted) showMessage(context, S.slotAdded);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text(S.addSlot),
              )
            : null,
        body: WeekView(
          slots: data.slots,
          showTeacher: true,
          bottomPadding: 96,
          onDelete: data.editable
              ? (s) async {
                  if (!await confirmDialog(context, title: S.removeSlotAsk, message: '${s.subject} · ${S.days[s.weekday - 1]} ${s.start}-${s.end}', confirm: S.remove, danger: true)) return;
                  try {
                    await ref.read(repoProvider).deleteSlot(s.id);
                    ref.invalidate(classTimetableProvider(classroomId));
                  } catch (e) {
                    if (context.mounted) reportError(context, e);
                  }
                }
              : null,
        ),
      ),
    );
  }
}

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _SlotSheet extends ConsumerStatefulWidget {
  const _SlotSheet({required this.classroomId, required this.teachers});
  final int classroomId;
  final List<TimetableTeacher> teachers;

  @override
  ConsumerState<_SlotSheet> createState() => _SlotSheetState();
}

class _SlotSheetState extends ConsumerState<_SlotSheet> {
  int _day = 1;
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 0);
  int? _subject;
  int? _teacher;
  final _room = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _room.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final t = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    setState(() {
      if (start) {
        _start = t;
        // keep a sensible hour for the end when it would come before the start
        if (_end.hour * 60 + _end.minute <= t.hour * 60 + t.minute) _end = TimeOfDay(hour: (t.hour + 1) % 24, minute: t.minute);
      } else {
        _end = t;
      }
    });
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
      await ref.read(repoProvider).addSlot(widget.classroomId, weekday: _day, start: _hhmm(_start), end: _hhmm(_end), subjectId: _subject!, teacherId: _teacher, room: _room.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(subjectsProvider);
    final label = Theme.of(context).textTheme.labelMedium;
    final eligible = _subject == null ? widget.teachers : widget.teachers.where((t) => t.gives(_subject!)).toList();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(S.addSlot, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Space.md),
        Text(S.day, style: label),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (var d = 1; d <= 6; d++) ChoiceChip(label: Text(S.daysShort[d - 1]), selected: _day == d, onSelected: (_) => setState(() => _day = d))]),
        const SizedBox(height: Space.md),
        Row(children: [
          Expanded(child: InkWell(onTap: () => _pick(true), child: InputDecorator(decoration: const InputDecoration(labelText: S.startTime, suffixIcon: Icon(Icons.schedule_outlined)), child: Text(_hhmm(_start))))),
          const SizedBox(width: Space.md),
          Expanded(child: InkWell(onTap: () => _pick(false), child: InputDecorator(decoration: const InputDecoration(labelText: S.endTime, suffixIcon: Icon(Icons.schedule_outlined)), child: Text(_hhmm(_end))))),
        ]),
        const SizedBox(height: Space.md),
        Text(S.subject, style: label),
        const SizedBox(height: Space.sm),
        subjects.when(
          loading: () => const SkeletonBox(height: 40),
          error: (e, _) => Text(userMessage(e)),
          data: (list) => list.isEmpty
              ? const Text(S.noSubjects)
              : Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final s in list) ChoiceChip(label: Text(s.name), selected: _subject == s.id, onSelected: (_) => setState(() { _subject = s.id; _teacher = null; }))]),
        ),
        const SizedBox(height: Space.md),
        Text('Enseignant', style: label),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          ChoiceChip(label: const Text(S.noTeacher), selected: _teacher == null, onSelected: (_) => setState(() => _teacher = null)),
          for (final t in eligible) ChoiceChip(label: Text(t.name), selected: _teacher == t.id, onSelected: (_) => setState(() => _teacher = t.id)),
        ]),
        if (widget.teachers.isEmpty) Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text("Aucun enseignant n'est affecté à cette classe (Profil > Classes).", style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: Space.md),
        TextField(controller: _room, decoration: const InputDecoration(labelText: 'Salle (facultatif)')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Semantics(liveRegion: true, child: Text(_error!, style: const TextStyle(color: Palette.danger)))),
        const SizedBox(height: Space.lg),
        BusyButton(label: S.addSlot, onPressed: _save, busy: _busy),
      ]),
    );
  }
}

/// A teacher's own week across all her classes.
class MyWeekPage extends ConsumerWidget {
  const MyWeekPage({super.key, this.now});
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(myWeekProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.myTimetable)),
      body: AsyncView<List<Slot>>(
        value: week,
        onRetry: () => ref.invalidate(myWeekProvider),
        data: (slots) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myWeekProvider);
            await ref.read(myWeekProvider.future);
          },
          child: WeekView(slots: slots, showClass: true, showTeacher: false, now: now, emptyMessage: "Aucun cours ne vous est encore attribué dans l'emploi du temps."),
        ),
      ),
    );
  }
}

/// The class timetable of one child (parent space), read-only.
class ChildTimetablePage extends ConsumerWidget {
  const ChildTimetablePage({super.key, required this.enrollmentId, required this.name, this.now});
  final int enrollmentId;
  final String name;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(childTimetableProvider(enrollmentId));
    return Scaffold(
      appBar: AppBar(title: Text('${S.timetable} · $name')),
      body: AsyncView<List<Slot>>(value: week, onRetry: () => ref.invalidate(childTimetableProvider(enrollmentId)), data: (slots) => WeekView(slots: slots, now: now)),
    );
  }
}
