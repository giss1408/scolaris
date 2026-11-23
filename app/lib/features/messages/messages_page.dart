import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/session.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Messages to families. "À envoyer": what the app composed and the secretary forwards from the school's WhatsApp (one tap opens WhatsApp with the text
/// ready). "Historique": where each message stands, and who must be phoned instead.
class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(title: const Text(S.messagesLog), bottom: const TabBar(tabs: [Tab(text: S.toSendTab), Tab(text: S.historyTab)])),
          body: const TabBarView(children: [ToSendTab(), _History()]),
        ),
      );
}

class ToSendTab extends ConsumerWidget {
  const ToSendTab({super.key});

  Future<void> _done(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(toSendProvider);
      ref.invalidate(messagesProvider);
      await ref.read(sessionProvider.notifier).refreshProfile();
    } catch (e) {
      if (context.mounted) reportError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(toSendProvider);
    final t = Theme.of(context).textTheme;
    return AsyncView<ToSendList>(
      value: list,
      onRetry: () => ref.invalidate(toSendProvider),
      data: (l) {
        if (l.schoolPhone == null) return const EmptyState(icon: Icons.phone_disabled_outlined, message: S.noNumberYet);
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(toSendProvider);
            await ref.read(toSendProvider.future);
          },
          child: ListView(padding: const EdgeInsets.all(Space.md), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(S.sendFromSchool, style: t.labelMedium),
                  const SizedBox(height: Space.xs),
                  Text(l.schoolPhone!, style: t.titleMedium),
                  const SizedBox(height: Space.sm),
                  Text(S.repliesHere, style: t.bodySmall),
                ]),
              ),
            ),
            if (!l.canSendNow) const Padding(padding: EdgeInsets.only(top: Space.md), child: InfoBanner(S.outsideSendHours, icon: Icons.schedule_outlined)),
            const SizedBox(height: Space.md),
            if (l.items.isEmpty) const SizedBox(height: 220, child: EmptyState(icon: Icons.mark_chat_read_outlined, message: S.nothingToSend)),
            for (final m in l.items)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text(m.family ?? '—', style: t.titleSmall)),
                        Flexible(child: StatusBadge(S.kindMsg(m.kind), icon: Icons.chat_outlined)),
                      ]),
                      const SizedBox(height: Space.sm),
                      Container(padding: const EdgeInsets.all(Space.md), decoration: BoxDecoration(color: Palette.page, borderRadius: BorderRadius.circular(Radii.sm)), child: Text(m.text, style: t.bodyMedium)),
                      const SizedBox(height: Space.md),
                      if (m.waLink != null)
                        FilledButton.icon(
                          onPressed: () async {
                            final ok = await launchUrl(Uri.parse(m.waLink!), mode: LaunchMode.externalApplication);
                            if (!context.mounted) return;
                            if (!ok) {
                              showMessage(context, "Impossible d'ouvrir WhatsApp.");
                              return;
                            }
                            if (await confirmDialog(context, title: S.sentAsk, message: m.family ?? '', confirm: 'Oui, envoyé') && context.mounted) {
                              await _done(context, ref, () => ref.read(repoProvider).markMessageSent(m.id));
                            }
                          },
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text(S.sendWhatsapp),
                        ),
                      const SizedBox(height: Space.sm),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: m.text)); if (context.mounted) showMessage(context, 'Message copié'); }, child: const Text('Copier'))),
                        const SizedBox(width: Space.sm),
                        Expanded(child: OutlinedButton(onPressed: () => _done(context, ref, () => ref.read(repoProvider).markMessageSent(m.id)), child: const Text(S.markSent))),
                      ]),
                      Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => _done(context, ref, () => ref.read(repoProvider).skipMessage(m.id)), child: const Text(S.skip))),
                    ]),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class _History extends ConsumerStatefulWidget {
  const _History();

  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  bool _onlyCalls = false;

  @override
  Widget build(BuildContext context) {
    final key = _onlyCalls ? 'failed,skipped' : null;
    final log = ref.watch(messagesProvider(key));
    return Column(children: [
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
      ]);
  }

  Tone _tone(String s) => switch (s) { 'failed' => Tone.danger, 'skipped' => Tone.warning, 'delivered' || 'read' => Tone.success, _ => Tone.neutral };
}
