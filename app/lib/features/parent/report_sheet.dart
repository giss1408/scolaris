import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// A parent tells the school that her child is absent for a day (today or coming days; the last 3 days to explain a past one).
Future<bool> showReportSheet(BuildContext context, {required int enrollmentId, required String childName}) async =>
    await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => ReportSheet(enrollmentId: enrollmentId, childName: childName, today: DateTime.now())) ?? false;

class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({super.key, required this.enrollmentId, required this.childName, required this.today});
  final int enrollmentId;
  final String childName;
  final DateTime today;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  late DateTime _day = DateTime(widget.today.year, widget.today.month, widget.today.day);
  String _reason = 'maladie';
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final t = DateTime(widget.today.year, widget.today.month, widget.today.day);
    final d = await showDatePicker(context: context, initialDate: _day, firstDate: t.subtract(const Duration(days: 3)), lastDate: t.add(const Duration(days: 14)), locale: const Locale('fr'));
    if (d != null) setState(() => _day = d);
  }

  Future<void> _send() async {
    if (_day.weekday == DateTime.sunday) {
      setState(() => _error = "Il n'y a pas classe le dimanche.");
      return;
    }
    if (_reason == 'autre' && _note.text.trim().length < 3) {
      setState(() => _error = S.reasonNoteRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).reportAbsence(widget.enrollmentId, _day, reason: _reason, note: _note.text);
      ref.invalidate(childReportsProvider(widget.enrollmentId));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(S.reportAbsence, style: t.titleLarge),
        const SizedBox(height: Space.xs),
        Text(widget.childName, style: t.bodyMedium?.copyWith(color: Palette.body)),
        const SizedBox(height: Space.md),
        InkWell(onTap: _pick, child: InputDecorator(decoration: const InputDecoration(labelText: S.reportDay, suffixIcon: Icon(Icons.calendar_today_outlined)), child: Text('${S.dayLong(_day.weekday)} ${formatDate(_day)}'))),
        const SizedBox(height: Space.md),
        Text(S.reasonTitle, style: t.labelMedium),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final r in const ['maladie', 'rendez_vous', 'famille', 'autre']) ChoiceChip(label: Text(S.reportReason(r)), selected: _reason == r, onSelected: (_) => setState(() { _reason = r; _error = null; })),
        ]),
        const SizedBox(height: Space.md),
        TextField(controller: _note, maxLength: 160, decoration: InputDecoration(labelText: _reason == 'autre' ? S.reasonNote : '${S.reasonNote} (facultatif)')),
        const InfoBanner(S.reportHelp, icon: Icons.info_outline),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Semantics(liveRegion: true, child: Text(_error!, style: const TextStyle(color: Palette.danger)))),
        const SizedBox(height: Space.lg),
        BusyButton(label: S.reportAbsence, onPressed: _send, busy: _busy),
      ]),
    );
  }
}
