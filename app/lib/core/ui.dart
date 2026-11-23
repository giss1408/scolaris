
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'errors.dart';
import 'money.dart';
import 'strings.dart';
import 'theme.dart';

/// Initials on a tinted circle (profile, list rows).
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40});
  final String name;
  final double size;

  static String initials(String n) {
    final p = n.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: c.primaryContainer,
        child: Text(initials(name), style: TextStyle(fontSize: size * .38, fontWeight: FontWeight.w600, color: c.onPrimaryContainer)),
      ),
    );
  }
}

enum Tone { neutral, success, warning, danger, info }

/// Colour AND icon AND text: status is never colour alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = Tone.neutral, this.icon});
  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      Tone.success => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      Tone.warning => (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      Tone.danger => (const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
      Tone.info => (const Color(0xFFE0F2F1), const Color(0xFF115E59)),
      Tone.neutral => (const Color(0xFFF1F5F9), const Color(0xFF334155)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg))),
      ]),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.hint, this.icon});
  final String label, value;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 18, color: Palette.body), const SizedBox(width: Space.sm)],
            Expanded(child: Text(label, style: t.labelMedium)),
          ]),
          const SizedBox(height: Space.sm),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: t.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
          if (hint != null) Text(hint!, style: t.bodySmall),
        ]),
      ),
    );
  }
}

class RowCard extends StatelessWidget {
  const RowCard({super.key, required this.title, this.subtitle, this.leading, this.trailing, this.onTap});
  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            child: Row(children: [
              if (leading != null) ...[leading!, const SizedBox(width: Space.md)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                  if (subtitle != null) Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: Space.sm), Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: trailing!))],
            ]),
          ),
        ),
      ),
    );
  }
}

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.name, required this.subtitle, this.badge, this.detail});
  final String name, subtitle;
  final Widget? badge;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Avatar(name, size: 72),
      const SizedBox(height: Space.md),
      Text(name, style: t.titleLarge, textAlign: TextAlign.center),
      Text(subtitle, style: t.bodyMedium?.copyWith(color: Palette.body), textAlign: TextAlign.center),
      if (badge != null) ...[const SizedBox(height: Space.sm), badge!],
      if (detail != null) ...[const SizedBox(height: Space.xs), Text(detail!, style: t.bodySmall)],
    ]);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.lg, 0, Space.sm),
        child: Row(children: [
          Expanded(child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(title),
        Card(child: Column(children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(indent: 56), children[i]]])),
      ]);
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.icon, required this.label, this.value, this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Palette.danger : null;
    return ListTile(
      minVerticalPadding: 12,
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      subtitle: value == null ? null : Text(value!),
      trailing: onTap == null || danger ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.height = 16, this.width, this.radius = Radii.sm});
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(color: const Color(0xFFE8EDF3), borderRadius: BorderRadius.circular(radius)),
      );
}

/// A list-shaped skeleton: what the content will look like, not a spinner.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 6});
  final int rows;

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.md),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
        itemBuilder: (_, __) => const Card(
          child: Padding(
            padding: EdgeInsets.all(Space.md),
            child: Row(children: [
              SkeletonBox(height: 40, width: 40, radius: 20),
              SizedBox(width: Space.md),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SkeletonBox(width: 160), SizedBox(height: 8), SkeletonBox(height: 12, width: 100)])),
            ]),
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: Palette.body),
            const SizedBox(height: Space.md),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (onAction != null) ...[const SizedBox(height: Space.md), FilledButton(onPressed: onAction, child: Text(actionLabel!))],
          ]),
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final forbidden = mapError(error).isForbidden;
    return EmptyState(
      icon: forbidden ? Icons.lock_outline : Icons.cloud_off_outlined,
      message: userMessage(error),
      actionLabel: forbidden ? null : S.retry,
      onAction: forbidden ? null : onRetry,
    );
  }
}

/// The four states of an async view in one place: loading skeleton, error with retry, empty, data.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.onRetry, required this.data, this.loading, this.isEmpty, this.empty});
  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T) data;
  final Widget? loading;
  final bool Function(T)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) => value.when(
        skipLoadingOnReload: true,
        loading: () => loading ?? const SkeletonList(),
        error: (e, _) => ErrorState(error: e, onRetry: onRetry),
        data: (v) => (isEmpty?.call(v) ?? false) && empty != null ? empty! : data(v),
      );
}

/// Full-width button that shows a spinner while it works and ignores taps meanwhile (no double submit).
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false, this.outlined = false, this.danger = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool outlined;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: outlined ? Palette.accent : Colors.white))
        : Text(label);
    final action = busy ? null : onPressed;
    if (outlined) {
      return OutlinedButton(
        onPressed: action,
        style: danger ? OutlinedButton.styleFrom(foregroundColor: Palette.danger, side: const BorderSide(color: Palette.danger)) : null,
        child: child,
      );
    }
    return FilledButton(onPressed: action, style: danger ? FilledButton.styleFrom(backgroundColor: Palette.danger) : null, child: child);
  }
}

/// Banner shown above the content (offline, session).
class InfoBanner extends StatelessWidget {
  const InfoBanner(this.message, {super.key, this.icon = Icons.info_outline});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: const Color(0xFFFEF3C7),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        child: Row(children: [Icon(icon, size: 18, color: const Color(0xFF92400E)), const SizedBox(width: Space.sm), Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFF92400E))))]),
      );
}

/// Thousands separator while typing: "150000" → "150 000". Digits only (FCFA has no decimals).
class FcfaInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final n = parseFcfa(newValue.text);
    if (n == null) return const TextEditingValue();
    final text = formatFcfa(n, unit: false);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, String confirm = S.confirm, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.cancel)),
        TextButton(onPressed: () => Navigator.pop(c, true), style: danger ? TextButton.styleFrom(foregroundColor: Palette.danger) : null, child: Text(confirm)),
      ],
    ),
  );
  return ok ?? false;
}
