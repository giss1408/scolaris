import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/repo.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Cancels ONE session (a date) of a period, with a reason. Returns true when the server accepted it.
Future<bool> showCancelSheet(BuildContext context, {required Slot slot, required DateTime date}) async =>
    await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => CancelSheet(slot: slot, date: date)) ?? false;

class CancelSheet extends ConsumerStatefulWidget {
  const CancelSheet({super.key, required this.slot, required this.date});
  final Slot slot;
  final DateTime date;

  @override
  ConsumerState<CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends ConsumerState<CancelSheet> {
  String _reason = 'maladie';
  int? _substitute;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == 'autre' && _note.text.trim().length < 3) {
      setState(() => _error = S.reasonNoteRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).cancelSession(widget.slot.id, widget.date, reason: _reason, note: _note.text, substituteStaffId: _substitute);
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
    final s = widget.slot;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(S.cancelCourse, style: t.titleLarge),
        const SizedBox(height: Space.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.subject} · ${s.classroom}', style: t.titleSmall),
              Text('${S.days[s.weekday - 1]} ${formatDate(widget.date)} · ${s.start}-${s.end}', style: t.bodySmall),
            ]),
          ),
        ),
        const SizedBox(height: Space.md),
        Text(S.reasonTitle, style: t.labelMedium),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final r in const ['maladie', 'absence_autorisee', 'formation', 'autre']) ChoiceChip(label: Text(S.reasonLabel(r)), selected: _reason == r, onSelected: (_) => setState(() { _reason = r; _error = null; })),
        ]),
        const SizedBox(height: Space.md),
        TextField(controller: _note, maxLength: 160, decoration: InputDecoration(labelText: _reason == 'autre' ? S.reasonNote : '${S.reasonNote} (facultatif)')),
        const InfoBanner(S.cancelInfo, icon: Icons.info_outline),
        if (ref.watch(meProvider).role != 'teacher') ..._substitutePicker(context),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Semantics(liveRegion: true, child: Text(_error!, style: const TextStyle(color: Palette.danger)))),
        const SizedBox(height: Space.lg),
        BusyButton(label: S.cancelCourse, onPressed: _submit, busy: _busy, danger: true),
      ]),
    );
  }

  /// The direction and the secretary can name a replacement right away; the absent teacher cannot choose her own.
  List<Widget> _substitutePicker(BuildContext context) {
    final teachers = ref.watch(teachersProvider).valueOrNull ?? const <TeacherRef>[];
    final others = teachers.where((x) => x.id != widget.slot.teacherId).toList();
    if (others.isEmpty) return const [];
    return [
      const SizedBox(height: Space.md),
      Text(S.substituteTitle, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: Space.xs),
      Text(S.substituteHelp, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: Space.sm),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        ChoiceChip(label: const Text(S.noSubstitute), selected: _substitute == null, onSelected: (_) => setState(() => _substitute = null)),
        for (final x in others) ChoiceChip(label: Text(x.name), selected: _substitute == x.id, onSelected: (_) => setState(() => _substitute = x.id)),
      ]),
    ];
  }
}
