import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// The roll of one COURSE (a period of the timetable) for one day. Everyone is present until the teacher says otherwise; saving tells the parents
/// of the absent or late pupils the same day (if the school switched automatic messages on and the parent agreed).
class CourseRollPage extends ConsumerStatefulWidget {
  const CourseRollPage({super.key, required this.slot, required this.date});
  final Slot slot;
  final DateTime date;

  @override
  ConsumerState<CourseRollPage> createState() => _CourseRollPageState();
}

class _CourseRollPageState extends ConsumerState<CourseRollPage> {
  List<RollRow>? _rows;
  final Map<int, String> _status = {}; // enrollmentId -> absence | retard (missing = present)
  final Set<int> _justified = {};
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
      final rows = await ref.read(repoProvider).courseRoll(widget.slot.id, widget.date);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        for (final r in rows) {
          if (r.status != 'present') {
            _status[r.enrollmentId] = r.status;
            if (r.justified) _justified.add(r.enrollmentId);
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(repoProvider).saveCourseRoll(widget.slot.id, widget.date, [for (final e in _status.entries) (enrollmentId: e.key, kind: e.value, justified: _justified.contains(e.key))]);
      if (mounted) {
        showMessage(context, '${S.rollSaved}. ${S.parentsTold(r.notified)}');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) reportError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slot;
    final t = Theme.of(context).textTheme;
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text(S.courseRoll)),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : rows == null
              ? const SkeletonList()
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
                    child: Align(alignment: Alignment.centerLeft, child: Text('${s.subject} · ${s.classroom} · ${formatDate(widget.date)} · ${s.start}-${s.end}', style: t.titleSmall)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    child: Align(alignment: Alignment.centerLeft, child: Text('${_status.values.where((x) => x == 'absence').length} absent(s) · ${_status.values.where((x) => x == 'retard').length} en retard', style: t.bodySmall)),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(Space.md),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final st = _status[r.enrollmentId];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(Space.sm),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [Avatar(r.name, size: 32), const SizedBox(width: Space.sm), Expanded(child: Text(r.name, style: t.titleSmall))]),
                              if (r.reportedReason != null || r.absentAllDay)
                                Padding(
                                  padding: const EdgeInsets.only(top: Space.sm),
                                  child: Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
                                    if (r.reportedReason != null) StatusBadge('${S.reportedByParent} : ${S.reportReason(r.reportedReason!)}', tone: Tone.info, icon: Icons.family_restroom_outlined),
                                    if (r.absentAllDay) const StatusBadge(S.absentAllDay, tone: Tone.warning, icon: Icons.event_busy_outlined),
                                  ]),
                                ),
                              const SizedBox(height: Space.sm),
                              Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
                                ChoiceChip(label: const Text(S.present), selected: st == null, onSelected: (_) => setState(() { _status.remove(r.enrollmentId); _justified.remove(r.enrollmentId); })),
                                ChoiceChip(label: const Text(S.absentLabel), selected: st == 'absence', onSelected: (_) => setState(() => _status[r.enrollmentId] = 'absence')),
                                ChoiceChip(label: const Text(S.late_), selected: st == 'retard', onSelected: (_) => setState(() => _status[r.enrollmentId] = 'retard')),
                                if (st != null) FilterChip(label: const Text('Justifié'), selected: _justified.contains(r.enrollmentId), onSelected: (v) => setState(() => v ? _justified.add(r.enrollmentId) : _justified.remove(r.enrollmentId))),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(child: Padding(padding: const EdgeInsets.all(Space.md), child: BusyButton(label: S.saveRoll, onPressed: _save, busy: _busy))),
                ]),
    );
  }
}
