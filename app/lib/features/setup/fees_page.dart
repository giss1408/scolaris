import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// The fee schedule of one level: the list of lines (what is due, how much, by when). One level at a time.
class FeesPage extends ConsumerStatefulWidget {
  const FeesPage({super.key});

  @override
  ConsumerState<FeesPage> createState() => _FeesPageState();
}

class _FeesPageState extends ConsumerState<FeesPage> {
  String? _level;
  List<FeeLine>? _lines;
  Object? _error;
  bool _busy = false;
  bool _dirty = false;

  Future<void> _load(String level) async {
    setState(() {
      _level = level;
      _lines = null;
      _error = null;
      _dirty = false;
    });
    try {
      final l = await ref.read(repoProvider).fees(ref.read(meProvider).yearId!, level);
      if (mounted) setState(() => _lines = l);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).saveFees(ref.read(meProvider).yearId!, _level!, _lines!);
      if (mounted) {
        setState(() => _dirty = false);
        showMessage(context, 'Frais enregistrés');
      }
    } catch (e) {
      if (mounted) showMessage(context, userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addLine() async {
    final line = await showModalBottomSheet<FeeLine>(context: context, isScrollControlled: true, builder: (_) => _LineSheet(kinds: ref.read(meProvider).feeKinds));
    if (line != null) {
      setState(() {
        _lines = [...?_lines, line]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        _dirty = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final levels = ref.watch(meProvider).levels.values.expand((e) => e).toList();
    final total = (_lines ?? const <FeeLine>[]).where((l) => !l.optional).fold<int>(0, (a, l) => a + l.amount);
    return Scaffold(
      appBar: AppBar(title: const Text(S.fees)),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            itemCount: levels.length,
            separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
            itemBuilder: (_, i) => ChoiceChip(label: Text(levels[i]), selected: _level == levels[i], onSelected: (_) => _load(levels[i])),
          ),
        ),
        Expanded(
          child: _level == null
              ? const EmptyState(icon: Icons.request_quote_outlined, message: 'Choisissez un niveau pour voir ou modifier ses frais.')
              : _error != null
                  ? ErrorState(error: _error!, onRetry: () => _load(_level!))
                  : _lines == null
                      ? const SkeletonList(rows: 4)
                      : ListView(padding: const EdgeInsets.all(Space.md), children: [
                          if (_lines!.isEmpty) const SizedBox(height: 160, child: EmptyState(icon: Icons.playlist_add, message: 'Aucun frais pour ce niveau.')),
                          for (var i = 0; i < _lines!.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.sm),
                              child: RowCard(
                                title: '${S.kindLabel(_lines![i].kind)} · ${_lines![i].label}',
                                subtitle: '${formatFcfa(_lines![i].amount)} · avant le ${formatDate(_lines![i].dueDate)}${_lines![i].optional ? ' · facultatif' : ''}${_lines![i].appliesTo == 'assigned' ? ' · affectés' : _lines![i].appliesTo == 'non_assigned' ? ' · non affectés' : ''}',
                                trailing: IconButton(tooltip: S.remove, icon: const Icon(Icons.delete_outline), onPressed: () => setState(() { _lines = [..._lines!]..removeAt(i); _dirty = true; })),
                              ),
                            ),
                          OutlinedButton.icon(onPressed: _addLine, icon: const Icon(Icons.add), label: const Text(S.addLine)),
                          const SizedBox(height: Space.md),
                          Text('Total obligatoire : ${formatFcfa(total)}', style: Theme.of(context).textTheme.titleSmall),
                        ]),
        ),
        if (_dirty) SafeArea(child: Padding(padding: const EdgeInsets.all(Space.md), child: BusyButton(label: S.save, onPressed: _save, busy: _busy))),
      ]),
    );
  }
}

class _LineSheet extends StatefulWidget {
  const _LineSheet({required this.kinds});
  final List<String> kinds;

  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _amount = TextEditingController();
  String _kind = 'scolarite';
  DateTime? _due;
  bool _optional = false;
  String _applies = 'all';

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(S.addLine, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.md),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final k in widget.kinds) ChoiceChip(label: Text(S.kindLabel(k)), selected: _kind == k, onSelected: (_) => setState(() => _kind = k))]),
            const SizedBox(height: Space.md),
            TextFormField(controller: _label, decoration: const InputDecoration(labelText: S.label, helperText: 'Ex. 1re tranche'), validator: (v) => (v ?? '').trim().isEmpty ? S.required : null),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, FcfaInputFormatter()],
              decoration: const InputDecoration(labelText: S.amount, suffixText: 'FCFA'),
              validator: (v) => (parseFcfa(v ?? '') ?? 0) <= 0 ? 'Entrez un montant' : null,
            ),
            const SizedBox(height: Space.md),
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, initialDate: _due ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 2), locale: const Locale('fr'));
                if (d != null) setState(() => _due = d);
              },
              child: InputDecorator(decoration: const InputDecoration(labelText: S.dueDate, suffixIcon: Icon(Icons.calendar_today_outlined)), child: Text(_due == null ? 'Choisir' : formatDate(_due!))),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text(S.optional), subtitle: const Text('Cantine, transport... choisi par la famille'), value: _optional, onChanged: (v) => setState(() => _optional = v)),
            Wrap(spacing: Space.sm, children: [for (final (v, l) in const [('all', 'Tous'), ('assigned', 'Affectés'), ('non_assigned', 'Non affectés')]) ChoiceChip(label: Text(l), selected: _applies == v, onSelected: (_) => setState(() => _applies = v))]),
            const SizedBox(height: Space.lg),
            FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                if (_due == null) {
                  showMessage(context, 'Choisissez la date limite');
                  return;
                }
                Navigator.pop(context, FeeLine(kind: _kind, label: _label.text.trim(), amount: parseFcfa(_amount.text)!, dueDate: _due!, optional: _optional, appliesTo: _applies));
              },
              child: const Text(S.addLine),
            ),
          ]),
        ),
      );
}
