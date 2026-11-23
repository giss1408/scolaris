import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// One field per pupil. A blank field means "not entered"; "Absent" is NOT a zero (the pupil is left out of the average).
class GradeEntryPage extends ConsumerStatefulWidget {
  const GradeEntryPage({super.key, required this.evaluationId});
  final int evaluationId;

  @override
  ConsumerState<GradeEntryPage> createState() => _GradeEntryPageState();
}

class _GradeEntryPageState extends ConsumerState<GradeEntryPage> {
  List<GradeRow>? _rows;
  final _controllers = <int, TextEditingController>{};
  final _absent = <int, bool>{};
  Evaluation? _eval;
  bool _locked = false;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final got = await ref.read(repoProvider).grades(widget.evaluationId);
      final rows = got.rows;
      final ev = got.evaluation;
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _eval = ev;
        _locked = ev.locked;
        for (final r in rows) {
          _controllers[r.enrollmentId] = TextEditingController(text: r.value == null ? '' : r.value!.replaceAll(RegExp(r'\.?0+$'), ''));
          _absent[r.enrollmentId] = r.absent;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    final max = _eval?.maxScore ?? 20;
    final out = <GradeRow>[];
    for (final r in _rows!) {
      final text = _controllers[r.enrollmentId]!.text.trim().replaceAll(',', '.');
      if (_absent[r.enrollmentId] == true) {
        out.add(GradeRow(enrollmentId: r.enrollmentId, name: r.name, absent: true));
      } else if (text.isNotEmpty) {
        final v = double.tryParse(text);
        if (v == null || v < 0 || v > max) {
          showMessage(context, '${r.name} : une note entre 0 et $max est attendue.');
          return;
        }
        out.add(GradeRow(enrollmentId: r.enrollmentId, name: r.name, value: text));
      } else {
        out.add(GradeRow(enrollmentId: r.enrollmentId, name: r.name));
      }
    }
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).saveGrades(widget.evaluationId, out);
      if (mounted) showMessage(context, 'Notes enregistrées');
    } catch (e) {
      if (mounted) reportError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleLock() async {
    try {
      await ref.read(repoProvider).setLocked(widget.evaluationId, !_locked);
      if (mounted) setState(() => _locked = !_locked);
    } catch (e) {
      if (mounted) reportError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.enterGrades),
        actions: [if (_locked) const Padding(padding: EdgeInsets.only(right: Space.md), child: Center(child: StatusBadge(S.lockedBadge, tone: Tone.success, icon: Icons.lock_outline)))],
      ),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : rows == null
              ? const SkeletonList()
              : Column(children: [
                  if (_locked) const InfoBanner('Évaluation validée : les notes ne peuvent plus être modifiées.', icon: Icons.lock_outline),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(Space.md),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final absent = _absent[r.enrollmentId] == true;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.name, style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: Space.sm),
                              Row(children: [
                                SizedBox(
                                  width: 96,
                                  child: TextField(
                                    controller: _controllers[r.enrollmentId],
                                    enabled: !_locked && !absent,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.center,
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                                    decoration: InputDecoration(hintText: '/${_eval?.maxScore ?? 20}', isDense: true),
                                  ),
                                ),
                                const SizedBox(width: Space.sm),
                                Flexible(child: FilterChip(label: const Text(S.absentLabel), selected: absent, onSelected: _locked ? null : (v) => setState(() => _absent[r.enrollmentId] = v))),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.md),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (!_locked) BusyButton(label: S.save, onPressed: _save, busy: _busy),
                        if (me.isDirector) TextButton.icon(onPressed: _toggleLock, icon: Icon(_locked ? Icons.lock_open_outlined : Icons.lock_outline), label: Text(_locked ? S.unlockEval : S.lockEval)),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
