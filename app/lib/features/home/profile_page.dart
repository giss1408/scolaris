import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../core/session.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// "Profil": who is signed in, the school, account settings, sign-out.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text(S.tabProfile)),
      body: ListView(padding: const EdgeInsets.all(Space.md), children: [
        const SizedBox(height: Space.sm),
        ProfileHeader(
          name: me.name,
          subtitle: me.schoolName,
          badge: StatusBadge(S.role(me.role), tone: Tone.info, icon: me.isDirector ? Icons.verified_user_outlined : Icons.badge_outlined),
          detail: me.city,
        ),
        SettingsGroup(title: S.account_, children: [
          SettingsRow(icon: Icons.lock_reset_outlined, label: S.changePassword, onTap: () => _changePassword(context, ref)),
        ]),
        if (me.isDirector)
          SettingsGroup(title: S.school, children: [
            SettingsRow(icon: Icons.event_outlined, label: 'Année scolaire', value: me.yearLabel ?? 'Aucune année en cours'),
            SettingsRow(icon: Icons.meeting_room_outlined, label: S.classes, onTap: () => context.push('/classes')),
            SettingsRow(icon: Icons.request_quote_outlined, label: S.fees, onTap: () => context.push('/fees')),
            SettingsRow(icon: Icons.group_outlined, label: S.team, onTap: () => context.push('/team')),
          ]),
        SettingsGroup(title: S.application, children: [
          const SettingsRow(icon: Icons.info_outline, label: 'Version', value: Config.version),
          SettingsRow(
            icon: Icons.logout,
            label: S.signOut,
            danger: true,
            onTap: () async {
              if (await confirmDialog(context, title: S.signOut, message: S.signOutAsk, confirm: S.signOut, danger: true)) {
                await ref.read(sessionProvider.notifier).signOut();
              }
            },
          ),
        ]),
        const SizedBox(height: Space.lg),
        Center(child: Text('${S.appName} · ${Config.version}', style: t.bodySmall)),
      ]),
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final done = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const _ChangePasswordSheet());
    if (done == true && context.mounted) showMessage(context, S.passwordChanged);
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).changePassword(_current.text, _next.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(S.changePassword, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.md),
            TextFormField(controller: _current, obscureText: true, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: S.currentPassword), validator: (v) => (v ?? '').isEmpty ? S.required : null),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: S.newPassword, helperText: '10 caractères minimum, avec lettres et chiffres'),
              validator: (v) => (v ?? '').length < 10 ? 'Au moins 10 caractères' : null,
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
            const SizedBox(height: Space.lg),
            BusyButton(label: S.save, onPressed: _save, busy: _busy),
          ]),
        ),
      );
}
