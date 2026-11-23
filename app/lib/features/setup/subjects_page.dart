import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Subjects of the school, and their coefficient for one level at a time (0 = shown on the report card but not counted).
class SubjectsPage extends ConsumerStatefulWidget {
  const SubjectsPage({super.key});

  @override
  ConsumerState<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends ConsumerState<SubjectsPage> {
  String? _level;
  Map<int, int>? _coefs;
  bool _dirty = false;
  bool _busy = false;

  Future<void> _pick(String level) async {
    setState(() {
      _level = level;
      _coefs = null;
      _dirty = false;
    });
    try {
      final c = await ref.read(repoProvider).coefficients(ref.read(meProvider).yearId!, level);
      if (mounted) setState(() => _coefs = {...c});
    } catch (e) {
      if (mounted) reportError(context, e);
    }
  }

  Future<void> _addSubject() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.addSubject),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: S.subject)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.cancel)), TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text(S.save))],
      ),
    );
    c.dispose();
    if (name == null || name.trim().length < 2) return;
    try {
      await ref.read(repoProvider).addSubject(name);
      ref.invalidate(subjectsProvider);
    } catch (e) {
      if (mounted) reportError(context, e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).saveCoefficients(ref.read(meProvider).yearId!, _level!, _coefs!);
      if (mounted) {
        setState(() => _dirty = false);
        showMessage(context, 'Coefficients enregistrés');
      }
    } catch (e) {
      if (mounted) reportError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final levels = ref.watch(meProvider).levels.values.expand((e) => e).toList();
    final subjects = ref.watch(subjectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.subjectsTitle), actions: [IconButton(tooltip: S.addSubject, icon: const Icon(Icons.add), onPressed: _addSubject)]),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            itemCount: levels.length,
            separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
            itemBuilder: (_, i) => ChoiceChip(label: Text(levels[i]), selected: _level == levels[i], onSelected: (_) => _pick(levels[i])),
          ),
        ),
        Expanded(
          child: AsyncView<List<Subject>>(
            value: subjects,
            onRetry: () => ref.invalidate(subjectsProvider),
            isEmpty: (l) => l.isEmpty,
            empty: EmptyState(icon: Icons.menu_book_outlined, message: 'Aucune matière pour le moment.', actionLabel: S.addSubject, onAction: _addSubject),
            data: (list) => ListView(padding: const EdgeInsets.all(Space.md), children: [
              if (_level == null) const Text('Choisissez un niveau pour régler les coefficients de ses matières.'),
              if (_level != null && _coefs == null) const SkeletonBox(height: 120, radius: Radii.md),
              if (_coefs != null)
                for (final s in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
                        child: Row(children: [
                          Expanded(child: Text(s.name, style: Theme.of(context).textTheme.titleSmall)),
                          IconButton(tooltip: 'Moins', icon: const Icon(Icons.remove_circle_outline), onPressed: (_coefs![s.id] ?? 0) <= 0 ? null : () => setState(() { _coefs![s.id] = (_coefs![s.id] ?? 0) - 1; _dirty = true; })),
                          SizedBox(width: 28, child: Text('${_coefs![s.id] ?? 0}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
                          IconButton(tooltip: 'Plus', icon: const Icon(Icons.add_circle_outline), onPressed: (_coefs![s.id] ?? 0) >= 20 ? null : () => setState(() { _coefs![s.id] = (_coefs![s.id] ?? 0) + 1; _dirty = true; })),
                        ]),
                      ),
                    ),
                  ),
            ]),
          ),
        ),
        if (_dirty) SafeArea(child: Padding(padding: const EdgeInsets.all(Space.md), child: BusyButton(label: S.save, onPressed: _save, busy: _busy))),
      ]),
    );
  }
}
