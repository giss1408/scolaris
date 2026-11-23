import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'errors.dart';
import 'session.dart';
import 'strings.dart';
import 'ui.dart';

/// Runs a money action that the server protects with a fresh password check. If the server asks for it
/// (`step_up_required`), the person re-enters her password once and the action is retried once.
Future<T?> withStepUp<T>(BuildContext context, WidgetRef ref, Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    final err = mapError(e);
    if (err.code != 'step_up_required' || !context.mounted) rethrow;
  }
  if (!context.mounted) return null;
  final admin = ref.read(sessionProvider).admin;
  final proof = await _askPassword(context, withTotp: admin); // the Scolaris team also re-types her authenticator code
  if (proof == null) return null;
  await ref.read(sessionProvider.notifier).stepUp(proof.password, totp: proof.totp);
  return action();
}

Future<({String password, String? totp})?> _askPassword(BuildContext context, {bool withTotp = false}) {
  final c = TextEditingController();
  final code = TextEditingController();
  return showDialog<({String password, String? totp})>(
    context: context,
    builder: (ctx) {
      var hidden = true;
      return StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Confirmer votre identité'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(S.rePassword),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              obscureText: hidden,
              autofocus: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: S.password, suffixIcon: IconButton(tooltip: 'Afficher', icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => set(() => hidden = !hidden))),
            ),
            if (withTotp) ...[
              const SizedBox(height: 12),
              TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: S.totpCode, counterText: '')),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.cancel)),
            TextButton(onPressed: () => Navigator.pop(ctx, (password: c.text, totp: code.text.isEmpty ? null : code.text)), child: const Text(S.confirm)),
          ],
        ),
      );
    },
  );
}

/// Shows the error as a message (never the raw exception).
void reportError(BuildContext context, Object e) {
  if (context.mounted) showMessage(context, userMessage(e));
}
