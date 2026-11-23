import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

String reportCardText(ReportCard c) => [
      c.school,
      'BULLETIN · ${S.periodLabel(c.period)} · ${c.classroom}',
      c.studentName,
      for (final l in c.lines) '${l.subject} (coef ${l.coef}) : ${l.average ?? '—'}',
      'Moyenne : ${c.average ?? '—'}${c.rank != null ? ' · Rang : ${c.rank}' : ''}',
      if (c.honour != null) S.honourLabel(c.honour!),
      if (c.appreciation != null) 'Appréciation : ${c.appreciation}',
    ].join('\n');

/// The report card as a paper-like page: header, subjects with coefficients, average, rank, conduct, absences, appreciation, decision.
class ReportCardPage extends ConsumerWidget {
  const ReportCardPage({super.key, required this.enrollmentId, required this.period, this.parent = false});
  final int enrollmentId, period;

  /// Opened from the parent space: her own child's card through the parent route, no editing.
  final bool parent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (enrollmentId: enrollmentId, period: period);
    final card = ref.watch(parent ? childReportCardProvider(key) : reportCardProvider(key));
    final me = parent ? null : ref.watch(meProvider);
    final classes = parent ? null : ref.watch(classroomsProvider).valueOrNull;
    final cardClass = card.valueOrNull?.classroom;
    // conduct and appreciation: the director and secretary, or a teacher only as the head teacher of THIS class (the server enforces it too)
    final canEdit = me != null && me.canGrade && (me.role != 'teacher' || (classes?.any((c) => c.name == cardClass && c.isHead) ?? false));
    return Scaffold(
      appBar: AppBar(title: const Text(S.reportCard)),
      body: AsyncView<ReportCard>(
        value: card,
        onRetry: () => ref.invalidate(parent ? childReportCardProvider(key) : reportCardProvider(key)),
        loading: const Padding(padding: EdgeInsets.all(Space.md), child: SkeletonBox(height: 400, radius: Radii.md)),
        data: (c) => ListView(padding: const EdgeInsets.all(Space.md), children: [
          _Paper(c),
          const SizedBox(height: Space.md),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: reportCardText(c))); if (context.mounted) showMessage(context, 'Bulletin copié'); }, icon: const Icon(Icons.copy_outlined), label: const Text('Copier'))),
            const SizedBox(width: Space.md),
            Expanded(child: FilledButton.icon(onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(reportCardText(c))}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.share_outlined), label: const Text(S.share))),
          ]),
          if (canEdit && period != 0) ...[
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(onPressed: () => _editRemark(context, ref, c), icon: const Icon(Icons.edit_outlined), label: const Text('Conduite, appréciation, décision')),
          ],
        ]),
      ),
    );
  }

  Future<void> _editRemark(BuildContext context, WidgetRef ref, ReportCard c) async {
    final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _RemarkSheet(enrollmentId: enrollmentId, period: period, card: c));
    if (saved == true) ref.invalidate(reportCardProvider((enrollmentId: enrollmentId, period: period)));
  }
}

class _Paper extends StatelessWidget {
  const _Paper(this.c);
  final ReportCard c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const mono = [FontFeature.tabularFigures()];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(c.school, textAlign: TextAlign.center, style: t.titleMedium),
          Text('Bulletin · ${S.periodLabel(c.period)}', textAlign: TextAlign.center, style: t.bodySmall),
          const SizedBox(height: Space.md),
          Row(children: [Avatar(c.studentName), const SizedBox(width: Space.md), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.studentName, style: t.titleSmall), Text(c.classroom, style: t.bodySmall)]))]),
          const Divider(height: Space.lg),
          Row(children: [Expanded(child: Text(S.subject, style: t.labelSmall)), SizedBox(width: 44, child: Text('Coef', textAlign: TextAlign.right, style: t.labelSmall)), SizedBox(width: 64, child: Text('Moy.', textAlign: TextAlign.right, style: t.labelSmall))]),
          const SizedBox(height: Space.xs),
          for (final l in c.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: Text(l.subject, style: t.bodyMedium)),
                SizedBox(width: 44, child: Text('${l.coef}', textAlign: TextAlign.right, style: t.bodyMedium?.copyWith(fontFeatures: mono))),
                SizedBox(width: 64, child: Text(l.average ?? '—', textAlign: TextAlign.right, style: t.titleSmall?.copyWith(fontFeatures: mono))),
              ]),
            ),
          const Divider(height: Space.lg),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(color: Palette.page, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Column(children: [
              _kv(context, S.average, c.average ?? '—', strong: true),
              _kv(context, S.rank, c.rank ?? '—'),
              if (c.classAverage != null) _kv(context, 'Moyenne de la classe', c.classAverage!),
              _kv(context, S.conduct, c.conduct ?? '—'),
            ]),
          ),
          const SizedBox(height: Space.md),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            if (c.honour != null) StatusBadge(S.honourLabel(c.honour!), tone: Tone.success, icon: Icons.emoji_events_outlined),
            if (c.passes == false) const StatusBadge('Moyenne < 10', tone: Tone.danger, icon: Icons.trending_down),
            if (c.sanction != null) StatusBadge(c.sanction!.replaceAll('_', ' '), tone: Tone.warning, icon: Icons.gavel_outlined),
            StatusBadge('${c.absUnjustified} abs. non justifiée(s)', icon: Icons.event_busy_outlined, tone: c.absUnjustified > 0 ? Tone.warning : Tone.neutral),
            StatusBadge('${c.absJustified} justifiée(s) · ${c.late} retard(s)', icon: Icons.schedule_outlined),
          ]),
          if (c.appreciation != null) ...[const SizedBox(height: Space.md), Text('${S.appreciation} : ${c.appreciation}', style: t.bodyMedium)],
          if (c.decision != null) ...[const SizedBox(height: Space.sm), Text('${S.decision} : ${c.decision}', style: t.titleSmall)],
        ]),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {bool strong = false}) {
    final t = Theme.of(context).textTheme;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(k, style: t.labelMedium)), Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: strong ? t.headlineSmall : t.titleSmall)))]));
  }
}

class _RemarkSheet extends ConsumerStatefulWidget {
  const _RemarkSheet({required this.enrollmentId, required this.period, required this.card});
  final int enrollmentId, period;
  final ReportCard card;

  @override
  ConsumerState<_RemarkSheet> createState() => _RemarkSheetState();
}

class _RemarkSheetState extends ConsumerState<_RemarkSheet> {
  late final _conduct = TextEditingController(text: widget.card.conduct ?? '');
  late final _appreciation = TextEditingController(text: widget.card.appreciation ?? '');
  String? _decision;
  String? _sanction;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _conduct.dispose();
    _appreciation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final conduct = _conduct.text.trim().replaceAll(',', '.');
    if (conduct.isNotEmpty && (double.tryParse(conduct) ?? 99) > 20) {
      setState(() => _error = 'La conduite est notée de 0 à 20.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).saveRemark(widget.enrollmentId, period: widget.period, conduct: conduct.isEmpty ? null : conduct, appreciation: _appreciation.text.trim().isEmpty ? null : _appreciation.text.trim(), sanction: _sanction, decision: _decision);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final director = ref.watch(meProvider).isDirector;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Conduite et appréciation', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Space.md),
        TextField(controller: _conduct, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: S.conduct)),
        const SizedBox(height: Space.md),
        TextField(controller: _appreciation, maxLength: 240, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: S.appreciation)),
        if (director) ...[
          Text(S.sanction, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final (v, l) in const [('avertissement_travail', 'Avertissement travail'), ('avertissement_conduite', 'Avertissement conduite'), ('blame', 'Blâme')]) ChoiceChip(label: Text(l), selected: _sanction == v, onSelected: (s) => setState(() => _sanction = s ? v : null))]),
          const SizedBox(height: Space.md),
          Text(S.decision, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final (v, l) in const [('passage', 'Passage'), ('redoublement', 'Redoublement'), ('reorientation', 'Réorientation'), ('exclusion', 'Exclusion')]) ChoiceChip(label: Text(l), selected: _decision == v, onSelected: (s) => setState(() => _decision = s ? v : null))]),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
        const SizedBox(height: Space.lg),
        BusyButton(label: S.save, onPressed: _save, busy: _busy),
      ]),
    );
  }
}
