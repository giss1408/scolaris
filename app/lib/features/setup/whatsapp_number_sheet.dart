import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// The school's own WhatsApp number: the one the secretary forwards messages from and the one parents reply to.
class WhatsappNumberSheet extends ConsumerStatefulWidget {
  const WhatsappNumberSheet({super.key});

  @override
  ConsumerState<WhatsappNumberSheet> createState() => _WhatsappNumberSheetState();
}

class _WhatsappNumberSheetState extends ConsumerState<WhatsappNumberSheet> {
  late final _phone = TextEditingController(text: ref.read(meProvider).whatsappPhone ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _run(String? number, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).setWhatsappPhone(number);
      await ref.read(sessionProvider.notifier).refreshProfile();
      if (mounted) {
        showMessage(context, done);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = ref.watch(meProvider).whatsappPhone != null;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.md, 0, Space.md, MediaQuery.viewInsetsOf(context).bottom + Space.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(S.schoolWhatsapp, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Space.sm),
        Text(S.schoolWhatsappHelp, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Space.md),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
          decoration: const InputDecoration(labelText: S.phone, helperText: S.phoneHelp, prefixIcon: Icon(Icons.chat_outlined)),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Semantics(liveRegion: true, child: Text(_error!, style: const TextStyle(color: Palette.danger)))),
        const SizedBox(height: Space.lg),
        BusyButton(label: S.save, onPressed: () => _phone.text.replaceAll(RegExp(r'\D'), '').length < 10 ? setState(() => _error = 'Entrez les 10 chiffres du numéro') : _run(_phone.text, S.whatsappNumberSaved), busy: _busy),
        if (has) ...[const SizedBox(height: Space.sm), BusyButton(label: S.removeNumber, outlined: true, danger: true, onPressed: () => _run(null, 'Numéro retiré.'), busy: _busy)],
      ]),
    );
  }
}
