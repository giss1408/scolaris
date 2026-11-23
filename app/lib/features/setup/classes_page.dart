import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

class ClassesPage extends ConsumerWidget {
  const ClassesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(classroomsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.classes)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const _AddClassSheet()) == true) ref.invalidate(classroomsProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text(S.addClass),
      ),
      body: AsyncView<List<Classroom>>(
        value: rooms,
        onRetry: () => ref.invalidate(classroomsProvider),
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.meeting_room_outlined, message: "Aucune classe pour cette année. Ajoutez la première."),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
          itemBuilder: (context, i) => RowCard(
            leading: const Icon(Icons.meeting_room_outlined),
            title: list[i].name,
            subtitle: 'Niveau ${list[i].level} · ${S.classTeachers}',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/classes/${list[i].id}/teachers?name=${Uri.encodeComponent(list[i].name)}'),
          ),
        ),
      ),
    );
  }
}

class _AddClassSheet extends ConsumerStatefulWidget {
  const _AddClassSheet();

  @override
  ConsumerState<_AddClassSheet> createState() => _AddClassSheetState();
}

class _AddClassSheetState extends ConsumerState<_AddClassSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  String? _level;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_level == null) {
      setState(() => _error = 'Choisissez un niveau');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).addClassroom(ref.read(meProvider).yearId!, _level!, _name.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final levels = ref.watch(meProvider).levels;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(S.addClass, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.md),
          Text(S.level, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final l in levels.values.expand((e) => e)) ChoiceChip(label: Text(l), selected: _level == l, onSelected: (_) => setState(() { _level = l; if (_name.text.isEmpty) _name.text = '$l A'; }))]),
          const SizedBox(height: Space.md),
          TextFormField(controller: _name, decoration: const InputDecoration(labelText: S.className, helperText: 'Ex. 6e 1, CM2 A'), validator: (v) => (v ?? '').trim().isEmpty ? S.required : null),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
          const SizedBox(height: Space.lg),
          BusyButton(label: S.save, onPressed: _save, busy: _busy),
        ]),
      ),
    );
  }
}
