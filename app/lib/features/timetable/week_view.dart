import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// One week of periods: a chip per day (today first selected), then that day's periods in time order.
/// `now` is injectable so the "En cours" / "Prochain" badges can be tested.
class WeekView extends StatefulWidget {
  const WeekView({super.key, required this.slots, this.showClass = false, this.showTeacher = true, this.onDelete, this.now, this.emptyMessage = S.noWeek, this.bottomPadding = Space.xl});
  final List<Slot> slots;
  final bool showClass, showTeacher;
  final void Function(Slot)? onDelete;
  final DateTime? now;
  final String emptyMessage;
  final double bottomPadding;

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  late int _day = _initialDay();

  DateTime get _now => widget.now ?? DateTime.now();

  int _initialDay() {
    final wd = _now.weekday; // 1 = Monday ... 7 = Sunday
    return wd > 6 ? 1 : wd;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final today = _now.weekday;
    final nowMin = _now.hour * 60 + _now.minute;
    final slots = widget.slots.where((s) => s.weekday == _day).toList()..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final next = _day == today ? slots.where((s) => s.startMinutes > nowMin).firstOrNull : null;
    return Column(children: [
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
                // a dot says "something is planned that day" without relying on colour alone: the number of periods
                tooltip: '${S.days[d - 1]} · ${widget.slots.where((s) => s.weekday == d).length} cours',
              ),
            ),
        ]),
      ),
      Expanded(
        child: slots.isEmpty
            ? EmptyState(icon: Icons.event_available_outlined, message: widget.slots.isEmpty ? widget.emptyMessage : S.noClassToday)
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, widget.bottomPadding),
                itemCount: slots.length,
                separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
                itemBuilder: (context, i) {
                  final s = slots[i];
                  final live = _day == today && nowMin >= s.startMinutes && nowMin < s.endMinutes;
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
                            Text(widget.showClass ? '${s.subject} · ${s.classroom}' : s.subject, style: t.titleSmall),
                            const SizedBox(height: 2),
                            Text([if (widget.showTeacher) s.teacher ?? S.noTeacher, if (s.room != null) '${S.room} ${s.room}'].join(' · '), style: t.bodySmall),
                            if (live || identical(s, next)) Padding(padding: const EdgeInsets.only(top: Space.sm), child: StatusBadge(live ? S.nowBadge : S.nextBadge, tone: live ? Tone.success : Tone.info, icon: live ? Icons.play_circle_outline : Icons.schedule_outlined)),
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
