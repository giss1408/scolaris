import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/repo.dart';
import '../../core/sensitive.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// The text of a receipt, for WhatsApp or the clipboard. Same data as the screen.
String receiptText(Receipt r) => [
      r.school,
      '${r.isCreditNote ? 'AVOIR' : 'REÇU'} ${r.number}',
      formatDate(r.date),
      'Élève : ${r.studentName} (${r.classroom})',
      '${r.isCreditNote ? 'Remboursement' : 'Montant'} : ${formatFcfa(r.amount.abs())} · ${S.methodLabel(r.method)}',
      'Reste à payer : ${formatFcfa(r.remainingAfter)}',
      'Merci de votre confiance.',
    ].join('\n');

class ReceiptPage extends ConsumerWidget {
  const ReceiptPage({super.key, required this.paymentId, this.justPaid = false});
  final int paymentId;
  final bool justPaid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(receiptProvider(paymentId));
    return Scaffold(
      appBar: AppBar(title: Text(justPaid ? S.paymentDone : 'Reçu')),
      body: AsyncView<Receipt>(
        value: r,
        onRetry: () => ref.invalidate(receiptProvider(paymentId)),
        loading: const Padding(padding: EdgeInsets.all(Space.md), child: SkeletonBox(height: 360, radius: Radii.md)),
        data: (rc) => SafeArea(
          child: ListView(padding: const EdgeInsets.all(Space.md), children: [
            if (justPaid) ...[
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle, color: Palette.success), SizedBox(width: Space.sm), Text(S.paymentDone, style: TextStyle(fontWeight: FontWeight.w600))]),
              const SizedBox(height: Space.md),
            ],
            _Paper(rc),
            const SizedBox(height: Space.md),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => _copy(context, rc), icon: const Icon(Icons.copy_outlined), label: const Text('Copier'))),
              const SizedBox(width: Space.md),
              Expanded(child: FilledButton.icon(onPressed: () => _share(context, rc), icon: const Icon(Icons.share_outlined), label: const Text(S.share))),
            ]),
            if (justPaid) ...[const SizedBox(height: Space.sm), TextButton(onPressed: () => context.pop(), child: const Text(S.finish))],
            if (!rc.isCreditNote && !justPaid && ref.watch(meProvider).canCollect) ...[
              const SizedBox(height: Space.lg),
              BusyButton(label: S.cancelPayment, outlined: true, danger: true, onPressed: () => _cancel(context, ref)),
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, Receipt r) async {
    await Clipboard.setData(ClipboardData(text: receiptText(r)));
    if (context.mounted) showMessage(context, 'Reçu copié');
  }

  Future<void> _share(BuildContext context, Receipt r) async {
    final ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(receiptText(r))}'), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) await _copy(context, r);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(S.cancelPayment),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Un avoir sera créé. Le paiement reste visible dans l\'historique.'),
          const SizedBox(height: Space.md),
          TextField(controller: reason, autofocus: true, decoration: const InputDecoration(labelText: S.cancelReason)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(S.back)),
          TextButton(onPressed: () => Navigator.pop(c, true), style: TextButton.styleFrom(foregroundColor: Palette.danger), child: const Text(S.cancelPayment)),
        ],
      ),
    );
    if (go != true || reason.text.trim().length < 3) {
      if (go == true && context.mounted) showMessage(context, 'Indiquez le motif (3 caractères minimum).');
      return;
    }
    if (!context.mounted) return;
    try {
      final done = await withStepUp(context, ref, () => ref.read(repoProvider).cancelPayment(paymentId, reason.text).then((_) => true));
      if (done == true && context.mounted) {
        ref.invalidate(dashboardProvider);
        ref.invalidate(arrearsProvider);
        showMessage(context, 'Paiement annulé : un avoir a été créé.');
        context.pop();
      }
    } catch (e) {
      if (context.mounted) reportError(context, e);
    }
  }
}

/// Paper-like card (receipt as printed): number, school, lines, amount.
class _Paper extends StatelessWidget {
  const _Paper(this.r);
  final Receipt r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget row(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(k, style: t.bodySmall)),
            const SizedBox(width: Space.md),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: bold ? t.titleSmall : t.bodyMedium)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(r.school, textAlign: TextAlign.center, style: t.titleMedium),
          if (r.city != null) Text(r.city!, textAlign: TextAlign.center, style: t.bodySmall),
          const SizedBox(height: Space.md),
          Center(child: StatusBadge(r.isCreditNote ? 'AVOIR ${r.number}' : 'REÇU ${r.number}', tone: r.isCreditNote ? Tone.danger : Tone.info, icon: Icons.receipt_long_outlined)),
          const Divider(height: Space.lg),
          row('Date', formatDate(r.date)),
          row('Année scolaire', r.year),
          row('Élève', r.studentName, bold: true),
          row('Classe', r.classroom),
          row('N° élève', r.internalNumber),
          const Divider(height: Space.lg),
          row('Moyen', S.methodLabel(r.method)),
          if (r.reference != null) row('Référence', r.reference!),
          if (r.reason != null) row('Motif', r.reason!),
          const SizedBox(height: Space.sm),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(color: Palette.page, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Row(children: [
              Expanded(child: Text(r.isCreditNote ? 'Remboursé' : 'Montant reçu', style: t.labelMedium)),
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatFcfa(r.amount.abs()), style: t.headlineSmall))),
            ]),
          ),
          const SizedBox(height: Space.sm),
          row('Reste à payer', formatFcfa(r.remainingAfter)),
          row('Encaissé par', r.cashier),
        ]),
      ),
    );
  }
}
