import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// What was sent to families by WhatsApp, where each message stands, and who must be phoned instead.
class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key});

  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  bool _onlyCalls = false;

  @override
  Widget build(BuildContext context) {
    final key = _onlyCalls ? 'failed,skipped' : null;
    final log = ref.watch(messagesProvider(key));
    return Scaffold(
      appBar: AppBar(title: const Text(S.messagesLog)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
          child: Align(alignment: Alignment.centerLeft, child: FilterChip(label: const Text(S.toCall), avatar: const Icon(Icons.call_outlined, size: 18), selected: _onlyCalls, onSelected: (v) => setState(() => _onlyCalls = v))),
        ),
        Expanded(
          child: AsyncView<MessageLog>(
            value: log,
            onRetry: () => ref.invalidate(messagesProvider(key)),
            isEmpty: (l) => l.items.isEmpty,
            empty: const EmptyState(icon: Icons.mark_chat_read_outlined, message: S.messagesEmpty),
            data: (l) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(messagesProvider(key));
                await ref.read(messagesProvider(key).future);
              },
              child: ListView(padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xl), children: [
                if (l.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: Space.md), child: Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [for (final e in l.summary.entries) StatusBadge('${S.statusLabel(e.key)} : ${e.value}', tone: _tone(e.key))])),
                for (final m in l.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(Space.md),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(m.family ?? '—', style: Theme.of(context).textTheme.titleSmall)),
                            Text(formatDate(m.createdAt), style: Theme.of(context).textTheme.bodySmall),
                          ]),
                          const SizedBox(height: Space.sm),
                          Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
                            StatusBadge(S.statusLabel(m.status), tone: _tone(m.status), icon: m.needsCall ? Icons.call_outlined : Icons.check_circle_outline),
                            StatusBadge(S.kindMsg(m.kind)),
                            if (m.needsCall) const StatusBadge(S.toCall, tone: Tone.warning, icon: Icons.phone_in_talk_outlined),
                          ]),
                          const SizedBox(height: Space.sm),
                          Text(m.text, style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Tone _tone(String s) => switch (s) { 'failed' => Tone.danger, 'skipped' => Tone.warning, 'delivered' || 'read' => Tone.success, _ => Tone.neutral };
}
