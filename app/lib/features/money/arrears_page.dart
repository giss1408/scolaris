import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Late payments, one row per FAMILY (siblings together), most owed first.
class ArrearsPage extends ConsumerWidget {
  const ArrearsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(arrearsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.tabArrears)),
      body: AsyncView<List<ArrearsFamily>>(
        value: rows,
        onRetry: () => ref.invalidate(arrearsProvider),
        isEmpty: (r) => r.isEmpty,
        empty: const EmptyState(icon: Icons.check_circle_outline, message: S.noArrears),
        data: (list) {
          final total = list.fold<int>(0, (a, f) => a + f.total);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(arrearsProvider);
              await ref.read(arrearsProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(Space.md),
              itemCount: list.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
              itemBuilder: (context, i) {
                if (i == 0) return StatCard(label: '${list.length} familles en retard', value: formatFcfa(total), icon: Icons.warning_amber_outlined);
                return _FamilyCard(list[i - 1]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard(this.f);
  final ArrearsFamily f;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(f.name),
            const SizedBox(width: Space.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(f.name, style: t.titleSmall), Text('${S.children(f.children.length)} · ${S.lateDays(f.oldestLateDays)}', style: t.bodySmall)])),
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatFcfa(f.total), style: t.titleSmall?.copyWith(color: Palette.danger)))),
          ]),
          const Divider(height: Space.lg),
          for (final c in f.children)
            InkWell(
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: () => context.push('/students/${c.studentId}?enrollment=${c.enrollmentId}&classroom=${Uri.encodeComponent(c.classroom)}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Row(children: [
                  Expanded(child: Text('${c.name} · ${c.classroom}', style: t.bodyMedium)),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatFcfa(c.overdue), style: t.bodyMedium))),
                  const Icon(Icons.chevron_right, size: 20),
                ]),
              ),
            ),
          if (f.contactPhone != null) ...[
            const SizedBox(height: Space.sm),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => launchUrl(Uri(scheme: 'tel', path: f.contactPhone), mode: LaunchMode.externalApplication), icon: const Icon(Icons.call_outlined), label: const Text(S.call))),
              const SizedBox(width: Space.sm),
              Expanded(child: OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('https://wa.me/${f.contactPhone!.replaceAll('+', '')}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.chat_outlined), label: const Text(S.whatsapp))),
            ]),
          ],
        ]),
      ),
    );
  }
}
