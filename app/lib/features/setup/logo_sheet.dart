import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/school_logo.dart';
import '../../core/session.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Picks an image from the phone. Injectable so tests do not open the gallery.
typedef ImagePick = Future<({Uint8List bytes, String contentType})?> Function();

Future<({Uint8List bytes, String contentType})?> pickFromGallery() async {
  // resized on the phone: a logo does not need more, and it keeps the upload small (the server accepts 512 KB at most)
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 90);
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  final lower = f.path.toLowerCase();
  return (bytes: bytes, contentType: lower.endsWith('.png') ? 'image/png' : 'image/jpeg');
}

final imagePickerProvider = Provider<ImagePick>((_) => pickFromGallery);

/// The school's logo: see it, choose another one, remove it.
class LogoSheet extends ConsumerStatefulWidget {
  const LogoSheet({super.key});

  @override
  ConsumerState<LogoSheet> createState() => _LogoSheetState();
}

class _LogoSheetState extends ConsumerState<LogoSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
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

  Future<void> _choose() async {
    final picked = await ref.read(imagePickerProvider)();
    if (picked == null) return;
    await _run(() => ref.read(repoProvider).uploadLogo(picked.bytes, picked.contentType), S.logoSaved);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(S.schoolLogo, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.md),
          Center(child: SchoolLogo(name: me.schoolName, version: me.logoVersion, size: 96)),
          const SizedBox(height: Space.sm),
          Text(S.logoHelp, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Semantics(liveRegion: true, child: Text(_error!, style: const TextStyle(color: Palette.danger)))),
          const SizedBox(height: Space.lg),
          BusyButton(label: S.pickLogo, onPressed: _choose, busy: _busy),
          if (me.hasLogo) ...[
            const SizedBox(height: Space.sm),
            BusyButton(label: S.removeLogo, outlined: true, danger: true, onPressed: () => _run(() => ref.read(repoProvider).deleteLogo(), 'Logo retiré.'), busy: _busy),
          ],
        ]),
      ),
    );
  }
}
