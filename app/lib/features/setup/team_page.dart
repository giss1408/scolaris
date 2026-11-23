import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

class TeamPage extends ConsumerWidget {
  const TeamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.team)),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _add(context, ref), icon: const Icon(Icons.person_add_alt_outlined), label: const Text(S.addMember)),
      body: AsyncView<List<StaffRow>>(
        value: staff,
        onRetry: () => ref.invalidate(staffProvider),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
          itemBuilder: (context, i) {
            final s = list[i];
            return RowCard(
              leading: Avatar(s.name),
              title: s.name,
              subtitle: S.role(s.role),
              trailing: !s.active
                  ? const StatusBadge('Retiré', tone: Tone.neutral, icon: Icons.block)
                  : s.role == 'director'
                      ? null
                      : IconButton(
                          tooltip: S.remove,
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () async {
                            if (!await confirmDialog(context, title: S.remove, message: '${s.name} ne pourra plus se connecter.', confirm: S.remove, danger: true)) return;
                            try {
                              await ref.read(repoProvider).removeStaff(s.id);
                              ref.invalidate(staffProvider);
                            } catch (e) {
                              if (context.mounted) reportError(context, e);
                            }
                          },
                        ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final added = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const _AddMemberSheet());
    if (added == true) {
      ref.invalidate(staffProvider);
      if (context.mounted) showMessage(context, S.memberAdded);
    }
  }
}

class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet();

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'accountant';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).addStaff(_name.text, _phone.text, _role);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(S.addMember, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.sm),
            Text(S.memberHelp, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Space.md),
            TextFormField(controller: _name, textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: S.memberName), validator: (v) => (v ?? '').trim().length < 2 ? S.required : null),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: const InputDecoration(labelText: S.phone, helperText: S.phoneHelp),
              validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? 'Entrez les 10 chiffres du numéro' : null,
            ),
            const SizedBox(height: Space.md),
            Text(S.memberRole, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, children: [for (final r in const ['accountant', 'secretary']) ChoiceChip(label: Text(S.role(r)), selected: _role == r, onSelected: (_) => setState(() => _role = r))]),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
            const SizedBox(height: Space.lg),
            BusyButton(label: S.addMember, onPressed: _save, busy: _busy),
          ]),
        ),
      );
}
