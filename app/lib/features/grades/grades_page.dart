import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Notes tab: pick a class, then work on its evaluations, results and roll call.
class GradesPage extends ConsumerWidget {
  const GradesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(classroomsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.gradesTitle)),
      body: AsyncView<List<Classroom>>(
        value: rooms,
        onRetry: () => ref.invalidate(classroomsProvider),
        isEmpty: (l) => l.isEmpty,
        empty: EmptyState(icon: Icons.meeting_room_outlined, message: ref.watch(meProvider).role == 'teacher' ? S.noClassAssigned : "Aucune classe n'est créée pour cette année."),
        data: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(classroomsProvider);
            await ref.read(classroomsProvider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(Space.md),
            itemCount: list.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
            itemBuilder: (context, i) {
              if (i == 0) return Text(S.pickClass, style: Theme.of(context).textTheme.labelMedium);
              final r = list[i - 1];
              return RowCard(
                leading: const Icon(Icons.menu_book_outlined, color: Palette.accent),
                title: r.name,
                subtitle: 'Niveau ${r.level}',
                trailing: r.isHead ? const StatusBadge(S.headTeacher, tone: Tone.info, icon: Icons.star_outline) : const Icon(Icons.chevron_right),
                onTap: () => context.push('/grades/class/${r.id}?name=${Uri.encodeComponent(r.name)}&level=${r.level}'),
              );
            },
          ),
        ),
      ),
    );
  }
}
