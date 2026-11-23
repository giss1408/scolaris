import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/logo.dart';
import '../../core/session.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _activating = false;
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(sessionProvider.notifier);
    try {
      if (_activating) {
        await session.activate(_phone.text, _code.text, _password.text);
      } else {
        await session.signIn(_phone.text, _password.text);
      }
    } catch (e) {
      final err = mapError(e);
      // Signing in with an account that was never activated: move to the activation form instead of a dead end.
      if (err.code == 'not_activated' && !_activating) {
        setState(() {
          _activating = true;
          _error = userMessage(err);
        });
      } else {
        setState(() => _error = userMessage(err));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final notice = ref.watch(sessionProvider).notice;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Align(alignment: Alignment.centerLeft, child: ScolarisLogo(size: 72)),
                    const SizedBox(height: Space.lg),
                    Text(_activating ? S.activateTitle : S.appName, style: t.headlineMedium),
                    const SizedBox(height: Space.sm),
                    Text(_activating ? S.activateHelp : "Gestion scolaire pour l'équipe de l'école.", style: t.bodyMedium?.copyWith(color: Palette.body)),
                    const SizedBox(height: Space.xl),
                    if (notice != null && _error == null) ...[InfoBanner(notice), const SizedBox(height: Space.md)],
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                      decoration: const InputDecoration(labelText: S.phone, helperText: S.phoneHelp, prefixIcon: Icon(Icons.phone_outlined)),
                      validator: (v) => (v == null || v.replaceAll(RegExp(r'\D'), '').length < 10) ? 'Entrez les 10 chiffres du numéro' : null,
                    ),
                    const SizedBox(height: Space.md),
                    if (_activating) ...[
                      TextFormField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        maxLength: 6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: S.activationCode, counterText: '', prefixIcon: Icon(Icons.pin_outlined)),
                        validator: (v) => (v ?? '').length != 6 ? 'Le code a 6 chiffres' : null,
                      ),
                      const SizedBox(height: Space.md),
                    ],
                    TextFormField(
                      controller: _password,
                      obscureText: _hidden,
                      textInputAction: TextInputAction.done,
                      autofillHints: [_activating ? AutofillHints.newPassword : AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: _activating ? S.newPassword : S.password,
                        helperText: _activating ? '10 caractères minimum, avec lettres et chiffres' : null,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(tooltip: _hidden ? 'Afficher le mot de passe' : 'Masquer le mot de passe', icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hidden = !_hidden)),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? S.required : (_activating && v.length < 10 ? 'Au moins 10 caractères' : null),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.md),
                      Semantics(liveRegion: true, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.error_outline, size: 18, color: Palette.danger),
                        const SizedBox(width: Space.sm),
                        Expanded(child: Text(_error!, style: t.bodyMedium?.copyWith(color: Palette.danger))),
                      ])),
                    ],
                    const SizedBox(height: Space.lg),
                    BusyButton(label: _activating ? S.activate : S.signIn, onPressed: _submit, busy: _busy),
                    const SizedBox(height: Space.sm),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() {
                        _activating = !_activating;
                        _error = null;
                      }),
                      child: Text(_activating ? S.backToSignIn : S.haveCode),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
