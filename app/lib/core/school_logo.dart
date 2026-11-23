import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'theme.dart';

/// The school's logo (or its initials when it has none). The image is fetched again only when `version` changes.
class SchoolLogo extends ConsumerWidget {
  const SchoolLogo({super.key, required this.name, this.version, this.parentSchoolId, this.size = 56});
  final String name;
  final String? version;

  /// Set in the parent space: the logo comes from the parent route for that school.
  final int? parentSchoolId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Uint8List?> logo = parentSchoolId != null ? ref.watch(parentLogoProvider((schoolId: parentSchoolId!, version: version))) : ref.watch(schoolLogoProvider(version));
    final bytes = logo.valueOrNull;
    final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    return Semantics(
      label: 'Logo de $name',
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: Palette.line)),
          alignment: Alignment.center,
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.contain, width: size, height: size, errorBuilder: (_, __, ___) => Text(initials, style: TextStyle(fontSize: size * .36, fontWeight: FontWeight.w700, color: Palette.accent)))
              : Text(initials, style: TextStyle(fontSize: size * .36, fontWeight: FontWeight.w700, color: Palette.accent)),
        ),
      ),
    );
  }
}
