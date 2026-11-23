import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// One week of periods: this week or next, a chip per day (today first), then that day's periods in time order, with real dates.
/// A cancelled session shows struck through with a "Cours annulé" badge (and the reason only when the server sent it: administration and
/// the teacher concerned). `now` is injectable so the badges can be tested.
class WeekView extends StatefulWidget {
  const WeekView({
    super.key,
    required this.slots,
    this.cancellations = const [],
    this.showClass = false,
    this.showTeacher = true,
    this.onDelete,
    this.onCancel,
    this.onRestore,
    this.onSubstitute,
    this.onRoll,
    this.canCancel,
    this.substitutions = const [],
    this.now,
    this.emptyMessage = S.noWeek,
    this.bottomPadding = Space.xl,
  });
  final List<Slot> slots;
  final List<Cancellation> cancellations;
  final bool showClass, showTeacher;
  final void Function(Slot)? onDelete;

  /// Cancel / restore ONE session (a date) of a period. Only offered for sessions that have not taken place yet, and where `canCancel` allows it.
  final void Function(Slot, DateTime)? onCancel;
  final void Function(Slot, DateTime)? onRestore;

  /// Choose or change the replacement teacher of a cancelled session (director, secretary).
  final void Function(Slot, DateTime)? onSubstitute;

  /// Call the roll of a session that has started today. Offered to the teacher of the period or her replacement.
  final void Function(Slot, DateTime)? onRoll;
  final bool Function(Slot)? canCancel;

  /// Sessions this teacher covers for a colleague (shown on their date, with a "Remplacement" badge).
  final List<({Slot slot, DateTime date})> substitutions;
  final DateTime? now;
  final String emptyMessage;
  final double bottomPadding;

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  late int _day = _initialDay();
  int _week = 0; // 0 = this week, 1 = next week

  DateTime get _now => widget.now ?? DateTime.now();

  int _initialDay() => _now.weekday > 6 ? 1 : _now.weekday;

  /// Monday of the week being shown. On a Sunday "this week" is the one starting tomorrow.
  DateTime get _monday {
    final today = DateTime(_now.year, _now.month, _now.day);
    final base = _now.weekday == 7 ? today.add(const Duration(days: 1)) : today.subtract(Duration(days: _now.weekday - 1));
    return base.add(Duration(days: 7 * _week));
  }

  DateTime _dateOf(int day) => _monday.add(Duration(days: day - 1));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final todayDate = DateTime(_now.year, _now.month, _now.day);
    final nowMin = _now.hour * 60 + _now.minute;
    final date = _dateOf(_day);
    final isToday = date == todayDate;
    final covering = widget.substitutions.where((x) => x.date == date).map((x) => x.slot).toList();
    final slots = [...widget.slots.where((s) => s.weekday == _day), ...covering]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    bool isCover(Slot s) => covering.any((c) => c.id == s.id);
    bool cancelled(Slot s) => widget.cancellations.any((c) => c.matches(s.id, date));
    final next = isToday ? slots.where((s) => s.startMinutes > nowMin && !cancelled(s)).firstOrNull : null;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, 0),
        child: SegmentedButton<int>(
          segments: const [ButtonSegment(value: 0, label: Text(S.thisWeek)), ButtonSegment(value: 1, label: Text(S.nextWeek))],
          selected: {_week},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _week = s.first),
        ),
      ),
      SizedBox(
        height: 56,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(Space.md), children: [
          for (var d = 1; d <= 6; d++)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: ChoiceChip(
                label: Text(S.daysShort[d - 1]),
                selected: _day == d,
                onSelected: (_) => setState(() => _day = d),
                tooltip: '${S.days[d - 1]} ${formatDate(_dateOf(d))} · ${widget.slots.where((s) => s.weekday == d).length} cours',
              ),
            ),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm), child: Align(alignment: Alignment.centerLeft, child: Text('${S.days[_day - 1]} ${formatDate(date)}', style: t.labelMedium))),
      Expanded(
        child: slots.isEmpty
            ? EmptyState(icon: Icons.event_available_outlined, message: widget.slots.isEmpty ? widget.emptyMessage : S.noClassToday)
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, widget.bottomPadding),
                itemCount: slots.length,
                separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
                itemBuilder: (context, i) {
                  final s = slots[i];
                  final cover = isCover(s);
                  final c = cover ? null : widget.cancellations.where((x) => x.matches(s.id, date)).firstOrNull;
                  final isCancelled = c != null;
                  final started = isToday && nowMin >= s.startMinutes;
                  final over = date.isBefore(todayDate) || (isToday && nowMin >= s.endMinutes);
                  final live = !isCancelled && isToday && nowMin >= s.startMinutes && nowMin < s.endMinutes;
                  final allowed = widget.canCancel?.call(s) ?? true;
                  final titleStyle = t.titleSmall?.copyWith(decoration: isCancelled ? TextDecoration.lineThrough : null, color: isCancelled ? Palette.body : null);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.md),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: 56,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.start, style: t.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                            Text(s.end, style: t.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                          ]),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(widget.showClass ? '${s.subject} · ${s.classroom}' : s.subject, style: titleStyle),
                            const SizedBox(height: 2),
                            Text([if (widget.showTeacher) s.teacher ?? S.noTeacher, if (s.room != null) '${S.room} ${s.room}'].join(' · '), style: t.bodySmall),
                            if (cover) const Padding(padding: EdgeInsets.only(top: Space.sm), child: StatusBadge(S.replacement, tone: Tone.info, icon: Icons.swap_horiz_outlined)),
                            if (isCancelled)
                              Padding(
                                padding: const EdgeInsets.only(top: Space.sm),
                                child: Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
                                  const StatusBadge(S.courseCancelled, tone: Tone.danger, icon: Icons.event_busy_outlined),
                                  if (c.reason != null) StatusBadge(S.reasonLabel(c.reason!), icon: Icons.info_outline),
                                  if (c.substitute != null) StatusBadge(S.replacedBy(c.substitute!), tone: Tone.info, icon: Icons.swap_horiz_outlined),
                                ]),
                              ),
                            if (isCancelled && c.note != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(c.note!, style: t.bodySmall)),
                            if (live || identical(s, next)) Padding(padding: const EdgeInsets.only(top: Space.sm), child: StatusBadge(live ? S.nowBadge : S.nextBadge, tone: live ? Tone.success : Tone.info, icon: live ? Icons.play_circle_outline : Icons.schedule_outlined)),
                            if (!over && allowed && !isCancelled && widget.onCancel != null)
                              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => widget.onCancel!(s, date), icon: const Icon(Icons.event_busy_outlined), label: const Text(S.cancelCourse))),
                            if (!over && isCancelled && widget.onSubstitute != null)
                              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => widget.onSubstitute!(s, date), icon: const Icon(Icons.swap_horiz_outlined), label: Text(c.substitute == null ? S.chooseSubstitute : S.changeSubstitute))),
                            if (!over && allowed && isCancelled && widget.onRestore != null)
                              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => widget.onRestore!(s, date), icon: const Icon(Icons.restore_outlined), label: const Text(S.restoreCourse))),
                            if (started && !isCancelled && widget.onRoll != null && (allowed || cover))
                              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => widget.onRoll!(s, date), icon: const Icon(Icons.fact_check_outlined), label: const Text(S.doRoll))),
                          ]),
                        ),
                        if (widget.onDelete != null) IconButton(tooltip: S.remove, icon: const Icon(Icons.delete_outline), onPressed: () => widget.onDelete!(s)),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
