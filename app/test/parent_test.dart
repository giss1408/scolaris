import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/features/auth/login_page.dart';
import 'package:scolaris/features/grades/report_card_page.dart';
import 'package:scolaris/features/parent/parent_pages.dart';

import 'helpers.dart';

void main() {
  void phone(WidgetTester t, {double h = 2000, double w = 390}) => t.view
    ..physicalSize = Size(w, h)
    ..devicePixelRatio = 1.0;

  testWidgets('a parent signs in to the parent space, not the staff app', (t) async {
    phone(t);
    final session = FakeSession(null);
    await t.pumpWidget(harness(const LoginPage(), me: null, session: session));
    await t.tap(find.text('Je suis parent'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).at(0), '07 01 02 03 04');
    await t.enterText(find.byType(TextFormField).at(1), 'MonMotDePasse2026');
    await t.tap(find.text('Se connecter').last);
    await t.pumpAndSettle();
    expect(session.calls, ['signIn parent=true']);
  });

  testWidgets('a parent creates her account, then is asked for the WhatsApp code', (t) async {
    phone(t, h: 2400);
    final session = FakeSession(null);
    await t.pumpWidget(harness(const LoginPage(), me: null, session: session));
    await t.tap(find.text('Je suis parent'));
    await t.pumpAndSettle();
    await t.tap(find.text('Créer mon compte'));
    await t.pumpAndSettle();
    expect(find.text('Votre nom'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).at(0), 'Traoré Moussa');
    await t.enterText(find.byType(TextFormField).at(1), '05 05 05 05 05');
    await t.enterText(find.byType(TextFormField).at(2), 'MonMotDePasse2026');
    await t.tap(find.text('Créer mon compte').last);
    await t.pumpAndSettle();
    expect(session.calls, ['register Traoré Moussa']);
    expect(find.textContaining('Un code vous sera envoyé sur WhatsApp'), findsOneWidget);
    expect(find.text('Code reçu (6 chiffres)'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).at(1), '123456');
    await t.enterText(find.byType(TextFormField).at(2), 'MonMotDePasse2026');
    await t.tap(find.text('Activer'));
    await t.pumpAndSettle();
    expect(session.calls.last, 'activate parent=true');
  });

  testWidgets('children of two schools with balance and lateness shown in text', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ChildrenPage(), me: null));
    await t.pumpAndSettle();
    expect(find.text('Fanta TRAORE'), findsOneWidget);
    expect(find.text('6e 1 · Ecole A'), findsOneWidget);
    expect(find.text('Moussa TRAORE'), findsOneWidget);
    expect(find.textContaining('en retard'), findsOneWidget);
    expect(find.text('Tout est réglé'), findsOneWidget);
  });

  testWidgets('no children attached: tells her to check her number with the school', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ChildrenPage(), me: null, repo: FakeRepo()..kids = const []));
    await t.pumpAndSettle();
    expect(find.textContaining('Aucun enfant'), findsOneWidget);
  });

  testWidgets('child page: report card entry, receipts and absences with text status', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ChildPage(enrollmentId: 10, name: 'Fanta TRAORE'), me: null));
    await t.pumpAndSettle();
    expect(find.textContaining('Voir le bulletin'), findsOneWidget);
    expect(find.text('REC-2026-000001 · 14/09/2026'), findsOneWidget);
    expect(find.text('Non justifiée'), findsOneWidget);
    expect(find.textContaining('au guichet'), findsOneWidget);
  });

  testWidgets('a parent opens the report card without the edit button', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ReportCardPage(enrollmentId: 10, period: 1, parent: true), me: null));
    await t.pumpAndSettle();
    expect(find.text('Mathématiques'), findsOneWidget);
    expect(find.text('Conduite, appréciation, décision'), findsNothing);
  });

  testWidgets('no overflow at 320 px, text x2: parent space', (t) async {
    phone(t, h: 640, w: 320);
    final problems = <String>[];
    for (final page in <Widget>[const LoginPage(), const ParentShell(), const ChildPage(enrollmentId: 10, name: 'Fanta TRAORE')]) {
      await t.pumpWidget(harness(page, me: null, textScale: 2.0));
      await t.pumpAndSettle();
      final e = t.takeException();
      if (e != null) problems.add('${page.runtimeType}: ${e.toString().split('\n').first}');
    }
    expect(problems, isEmpty);
  });
}
