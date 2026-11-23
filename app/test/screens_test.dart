import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/errors.dart';
import 'package:scolaris/core/session.dart';
import 'package:scolaris/features/auth/login_page.dart';
import 'package:scolaris/features/home/dashboard_page.dart';
import 'package:scolaris/features/home/profile_page.dart';
import 'package:scolaris/features/home/shell_page.dart';
import 'package:scolaris/features/money/arrears_page.dart';
import 'package:scolaris/features/money/receipt_page.dart';
import 'package:scolaris/features/students/student_detail_page.dart';
import 'package:scolaris/features/students/students_page.dart';

import 'helpers.dart';

void main() {
  // A tall phone so lazily built lists show everything the test looks for.
  void phone(WidgetTester t, {double h = 2000}) => t.view
    ..physicalSize = Size(390, h)
    ..devicePixelRatio = 1.0;

  testWidgets('login: empty form shows field errors, nothing is sent', (t) async {
    phone(t);
    await t.pumpWidget(harness(const LoginPage(), me: null));
    await t.tap(find.text('Se connecter').last);
    await t.pump();
    expect(find.text('Entrez les 10 chiffres du numéro'), findsOneWidget);
    expect(find.text('Champ obligatoire'), findsOneWidget);
  });

  testWidgets('login: a never-activated account moves to the activation form', (t) async {
    phone(t);
    await t.pumpWidget(harness(const LoginPage(), me: null, session: FakeSession(null, signInError: AppError('not_activated'))));
    await t.enterText(find.byType(TextFormField).at(0), '07 01 02 03 04');
    await t.enterText(find.byType(TextFormField).at(1), 'MonMotDePasse2026');
    await t.tap(find.text('Se connecter').last);
    await t.pumpAndSettle();
    expect(find.text('Activer mon compte'), findsOneWidget);
    expect(find.textContaining("pas encore activé"), findsOneWidget);
    expect(find.text('Code reçu (6 chiffres)'), findsOneWidget);
  });

  testWidgets('director sees four tabs, secretary only students and profile', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ShellPage(), me: meWith('director')));
    await t.pumpAndSettle();
    for (final l in ['Accueil', 'Élèves', 'Impayés', 'Profil']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(l)), findsOneWidget, reason: l);
    }
    await t.pumpWidget(harness(const ShellPage(), me: meWith('secretary')));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Impayés')), findsNothing);
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Accueil')), findsNothing);
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Élèves')), findsOneWidget);
  });

  testWidgets('dashboard: figures with FCFA, recovery, and the family to chase', (t) async {
    phone(t);
    await t.pumpWidget(harness(DashboardPage(goTo: (_) {}), me: meWith('director')));
    await t.pumpAndSettle();
    expect(find.text('Bonjour Awa'), findsOneWidget);
    expect(find.text('150 000 FCFA'), findsOneWidget);
    expect(find.text('40 %'), findsOneWidget);
    expect(find.text('KOUASSI'), findsOneWidget);
    expect(find.text('Encaisser'), findsOneWidget);
    expect(find.text('Nouvel élève'), findsOneWidget);
  });

  testWidgets('dashboard: an offline error shows a message and a retry, not an exception', (t) async {
    phone(t);
    await t.pumpWidget(harness(DashboardPage(goTo: (_) {}), me: meWith('accountant'), repo: FakeRepo(failDashboard: true)));
    await t.pumpAndSettle();
    expect(find.textContaining('Pas de connexion'), findsOneWidget);
    expect(find.text('Réessayer'), findsWidgets);
    expect(find.textContaining('AppError'), findsNothing);
  });

  testWidgets('arrears: one row per family with children and late days', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ArrearsPage(), me: meWith('accountant')));
    await t.pumpAndSettle();
    expect(find.text('1 familles en retard'), findsOneWidget);
    expect(find.textContaining('2 enfants'), findsOneWidget);
    expect(find.textContaining('Retard de 12 jours'), findsOneWidget);
    expect(find.text('Appeler'), findsOneWidget);
  });

  testWidgets('arrears: nothing late shows the empty state', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ArrearsPage(), me: meWith('accountant'), repo: FakeRepo()));
    await t.pumpAndSettle();
    expect(find.text('Aucun impayé. Bravo !'), findsOneWidget);
  });

  testWidgets('students list and student sheet with the account lines', (t) async {
    phone(t);
    await t.pumpWidget(harness(const StudentsPage(), me: meWith('secretary')));
    await t.pumpAndSettle();
    expect(find.text('KOUASSI Aya'), findsOneWidget);
    expect(find.text('Affecté'), findsOneWidget);
    expect(find.text('Nouvel élève'), findsOneWidget); // the secretary can enrol

    await t.pumpWidget(harness(const StudentDetailPage(studentId: 1, enrollmentId: 10, classroom: '6e 1'), me: meWith('accountant')));
    await t.pumpAndSettle();
    expect(find.text('KOUASSI Aya'), findsOneWidget);
    expect(find.text('Payé'), findsOneWidget);
    expect(find.text('En retard'), findsOneWidget); // status has text, not only colour
    expect(find.text('Encaisser'), findsOneWidget);
    expect(find.text('Accorder une réduction'), findsNothing); // director only
    expect(find.text('Appeler'), findsOneWidget);
    expect(find.text('REC-2026-000001 · 14/09/2026'), findsOneWidget);
  });

  testWidgets('a secretary sees no money on the student sheet', (t) async {
    phone(t);
    await t.pumpWidget(harness(const StudentDetailPage(studentId: 1, enrollmentId: 10, classroom: '6e 1'), me: meWith('secretary')));
    await t.pumpAndSettle();
    expect(find.text('Encaisser'), findsNothing);
    expect(find.text('Situation financière'), findsNothing);
  });

  testWidgets('receipt shows number, amount and remaining', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ReceiptPage(paymentId: 99, justPaid: true), me: meWith('accountant')));
    await t.pumpAndSettle();
    expect(find.text('REÇU REC-2026-000002'), findsOneWidget);
    expect(find.text('50 000 FCFA'), findsWidgets);
    expect(find.text('Paiement enregistré'), findsWidgets);
    expect(find.text('Partager'), findsOneWidget);
  });

  testWidgets('profile: avatar initials, role badge, school group only for the director, sign-out asks first', (t) async {
    phone(t, h: 4200); // the profile is long: build all of it
    final session = FakeSession(meWith('director'));
    await t.pumpWidget(harness(const ProfilePage(), me: null, session: session));
    await t.pumpAndSettle();
    expect(find.text('AK'), findsOneWidget);
    expect(find.text('Directeur / Directrice'), findsOneWidget);
    expect(find.text('Équipe'), findsOneWidget);
    await t.ensureVisible(find.text('Se déconnecter'));
    await t.tap(find.text('Se déconnecter'));
    await t.pumpAndSettle();
    expect(find.text('Se déconnecter de Scolaris ?'), findsOneWidget);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(session.signOuts, 0);

    await t.pumpWidget(harness(const ProfilePage(), me: meWith('accountant')));
    await t.pumpAndSettle();
    expect(find.text('Équipe'), findsNothing);
    expect(find.text('Frais de scolarité'), findsNothing);
  });

  testWidgets('no overflow at 320 px wide and text scale 2.0', (t) async {
    t.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1.0;
    final problems = <String>[];
    for (final page in <Widget>[
      const LoginPage(),
      DashboardPage(goTo: (_) {}),
      const ArrearsPage(),
      const StudentsPage(),
      const StudentDetailPage(studentId: 1, enrollmentId: 10, classroom: '6e 1'),
      const ReceiptPage(paymentId: 99),
      const ProfilePage(),
    ]) {
      await t.pumpWidget(harness(page, me: meWith('director'), textScale: 2.0));
      await t.pumpAndSettle();
      final e = t.takeException();
      if (e != null) problems.add('${page.runtimeType}: ${e.toString().split('\n').first}');
    }
    expect(problems, isEmpty);
  });

  test('session state starts loading', () {
    expect(const SessionState(SessionStatus.loading).me, isNull);
  });
}
