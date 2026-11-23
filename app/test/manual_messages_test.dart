import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/models.dart';
import 'package:scolaris/features/home/profile_page.dart';
import 'package:scolaris/features/messages/messages_page.dart';
import 'package:scolaris/features/setup/whatsapp_number_sheet.dart';
import 'package:scolaris/features/students/student_detail_page.dart';

import 'helpers.dart';

void main() {
  void phone(WidgetTester t, {double h = 2800, double w = 390}) => t.view
    ..physicalSize = Size(w, h)
    ..devicePixelRatio = 1.0;

  testWidgets('the secretary sees the number to send from, the messages to forward, and that replies come to the school', (t) async {
    phone(t);
    await t.pumpWidget(harness(const MessagesPage(), me: meWith('secretary')));
    await t.pumpAndSettle();
    expect(find.text("Envoyez depuis le numéro WhatsApp de l'école :"), findsOneWidget);
    expect(find.text('+2250705060708'), findsOneWidget);
    expect(find.text('Les réponses des parents arrivent sur ce numéro, dans votre WhatsApp.'), findsOneWidget);
    expect(find.text('KOUASSI'), findsOneWidget);
    expect(find.textContaining('Fanta a été noté(e) absent(e)'), findsOneWidget);
    expect(find.text('Envoyer sur WhatsApp'), findsNWidgets(2));
    expect(find.textContaining('mieux vaut envoyer ce message demain'), findsNothing); // inside the allowed hours
  });

  testWidgets('"Marquer comme envoyé" and "Passer" update the list and the profile count', (t) async {
    phone(t);
    final session = FakeSession(meWith('secretary'));
    final repo = FakeRepo();
    await t.pumpWidget(harness(const MessagesPage(), me: null, session: session, repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Marquer comme envoyé').first);
    await t.pumpAndSettle();
    expect(repo.forwarded, [1]);
    await t.tap(find.text('Passer').first);
    await t.pumpAndSettle();
    expect(repo.setAside, [1]);
    expect(session.refreshes, 2); // the "N à envoyer" shown in the profile is recomputed each time
  });

  testWidgets('outside the allowed hours the secretary is advised to wait', (t) async {
    phone(t);
    final repo = FakeRepo()..toSend = ToSendList(schoolPhone: '+2250705060708', canSendNow: false, items: FakeRepo().toSend.items);
    await t.pumpWidget(harness(const MessagesPage(), me: meWith('secretary'), repo: repo));
    await t.pumpAndSettle();
    expect(find.textContaining('mieux vaut envoyer ce message demain'), findsOneWidget);
  });

  testWidgets('without the school\'s number nothing is prepared, and the page says who must set it', (t) async {
    phone(t);
    final repo = FakeRepo()..toSend = const ToSendList(schoolPhone: null, canSendNow: true, items: []);
    await t.pumpWidget(harness(const MessagesPage(), me: meWith('secretary'), repo: repo));
    await t.pumpAndSettle();
    expect(find.textContaining("tant que le directeur n'a pas enregistré le numéro WhatsApp"), findsOneWidget);
    expect(find.text('Envoyer sur WhatsApp'), findsNothing);
  });

  testWidgets('nothing to forward is a clear empty state; the history tab keeps the filter for the families to phone', (t) async {
    phone(t);
    final repo = FakeRepo()..toSend = const ToSendList(schoolPhone: '+2250705060708', canSendNow: true, items: []);
    await t.pumpWidget(harness(const MessagesPage(), me: meWith('secretary'), repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Aucun message à envoyer.'), findsOneWidget);
    await t.tap(find.text('Historique'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilterChip, 'À appeler'));
    await t.pumpAndSettle();
    expect(repo.lastMessagesFilter, 'failed,skipped');
  });

  testWidgets('profile: the director enters the number; the secretary only sees how many messages wait', (t) async {
    phone(t, h: 3200);
    await t.pumpWidget(harness(const ProfilePage(), me: meWith('director', whatsappPhone: '+2250705060708', toSend: 3)));
    await t.pumpAndSettle();
    expect(find.text("Numéro WhatsApp de l'école"), findsOneWidget);
    expect(find.text('+2250705060708'), findsOneWidget);
    expect(find.text('3 à envoyer'), findsOneWidget);
    expect(find.text('Envoi automatique par Scolaris (avancé)'), findsOneWidget); // optional: the default is manual
    await t.pumpWidget(harness(const ProfilePage(), me: meWith('secretary', toSend: 1)));
    await t.pumpAndSettle();
    expect(find.text("Numéro WhatsApp de l'école"), findsNothing);
    expect(find.text('1 à envoyer'), findsOneWidget);
    await t.pumpWidget(harness(const ProfilePage(), me: meWith('director')));
    await t.pumpAndSettle();
    expect(find.text('Aucun'), findsWidgets); // no number yet
  });

  testWidgets('the number sheet refuses a short number, saves a valid one, and can remove it', (t) async {
    phone(t);
    final session = FakeSession(meWith('director'));
    final repo = FakeRepo();
    await t.pumpWidget(harness(const Scaffold(body: WhatsappNumberSheet()), me: null, session: session, repo: repo));
    await t.pumpAndSettle();
    expect(find.textContaining('les réponses des parents arrivent sur ce numéro'), findsOneWidget);
    await t.enterText(find.byType(TextField), '0705');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(find.text('Entrez les 10 chiffres du numéro'), findsOneWidget);
    expect(repo.whatsappNumbers, isEmpty);
    await t.enterText(find.byType(TextField), '07 05 06 07 08');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(repo.whatsappNumbers, ['07 05 06 07 08']);
    expect(session.refreshes, 1);
  });

  testWidgets('the number sheet offers to remove an existing number', (t) async {
    phone(t);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const Scaffold(body: WhatsappNumberSheet()), me: meWith('director', whatsappPhone: '+2250705060708'), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Retirer le numéro'));
    await t.pumpAndSettle();
    expect(repo.whatsappNumbers, [null]);
  });

  testWidgets('a parent who says stop: the staff withdraw her WhatsApp consent after a confirmation, and can restore it', (t) async {
    phone(t, h: 3000);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const StudentDetailPage(studentId: 1, enrollmentId: 10, classroom: '6e 1'), me: meWith('secretary'), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text("Retirer l'accord WhatsApp"));
    await t.pumpAndSettle();
    expect(find.textContaining('Plus aucun message WhatsApp ne sera préparé'), findsOneWidget);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(repo.optins, isEmpty);
    await t.tap(find.text("Retirer l'accord WhatsApp"));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, "Retirer l'accord WhatsApp"));
    await t.pumpAndSettle();
    expect(repo.optins.single, (id: 5, on: false));
  });

  testWidgets('no overflow at 320 px, text x2: messages to forward and the number sheet', (t) async {
    phone(t, h: 2800, w: 320);
    final problems = <String>[];
    for (final page in <Widget>[const MessagesPage(), const Scaffold(body: WhatsappNumberSheet())]) {
      await t.pumpWidget(harness(page, me: meWith('director', whatsappPhone: '+2250705060708'), textScale: 2.0));
      await t.pumpAndSettle();
      final e = t.takeException();
      if (e != null) problems.add('${page.runtimeType}: ${e.toString().split('\n').first}');
    }
    expect(problems, isEmpty);
  });
}
