import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/models.dart';
import 'package:scolaris/features/grades/class_page.dart';
import 'package:scolaris/features/grades/grade_entry_page.dart';
import 'package:scolaris/features/grades/grades_page.dart';
import 'package:scolaris/features/grades/report_card_page.dart';
import 'package:scolaris/features/home/shell_page.dart';
import 'package:scolaris/features/money/reminders_page.dart';
import 'package:scolaris/features/setup/subjects_page.dart';

import 'helpers.dart';

void main() {
  void phone(WidgetTester t, {double h = 2000, double w = 390}) => t.view
    ..physicalSize = Size(w, h)
    ..devicePixelRatio = 1.0;

  testWidgets('teacher: only Notes and Profil, no money anywhere', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ShellPage(), me: meWith('teacher')));
    await t.pumpAndSettle();
    final bar = find.byType(NavigationBar);
    expect(find.descendant(of: bar, matching: find.text('Notes')), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Profil')), findsOneWidget);
    for (final l in ['Accueil', 'Élèves', 'Impayés']) {
      expect(find.descendant(of: bar, matching: find.text(l)), findsNothing, reason: l);
    }
  });

  testWidgets('secretary: students and notes, no money tabs; director sees five tabs', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ShellPage(), me: meWith('secretary')));
    await t.pumpAndSettle();
    final bar = find.byType(NavigationBar);
    expect(find.descendant(of: bar, matching: find.text('Notes')), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Élèves')), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Impayés')), findsNothing);
    await t.pumpWidget(harness(const ShellPage(), me: meWith('director')));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.byType(NavigationDestination)), findsNWidgets(5));
  });

  testWidgets('class results are ordered by rank with honours; unranked pupils are said so', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ClassPage(classroomId: 1, name: '6e 1', level: '6e'), me: meWith('teacher')));
    await t.pumpAndSettle();
    await t.tap(find.text('Résultats'));
    await t.pumpAndSettle();
    expect(find.text('Moyenne de la classe : 12.50'), findsOneWidget);
    final first = t.getTopLeft(find.text('KOUASSI Aya')).dy;
    final second = t.getTopLeft(find.text('YAO Koffi')).dy;
    final unranked = t.getTopLeft(find.text('ZADI Mariam')).dy;
    expect(first < second && second < unranked, isTrue);
    expect(find.textContaining('1er · Félicitations'), findsOneWidget);
    expect(find.text('Pas encore classé(e)'), findsOneWidget);
    expect(find.text('< 10'), findsOneWidget); // a failing average carries text, not only colour
  });

  testWidgets('grade entry: out-of-range mark is refused, absent is not a zero, blank is kept blank', (t) async {
    phone(t);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const GradeEntryPage(evaluationId: 7), me: meWith('teacher'), repo: repo));
    await t.pumpAndSettle();
    expect(find.text('KOUASSI Aya'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '25');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(find.textContaining('entre 0 et 20'), findsOneWidget);
    expect(repo.savedGrades, isEmpty);
    await t.pump(const Duration(seconds: 5)); // let the message go: it floats over the button
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '14,5');
    await t.tap(find.widgetWithText(FilterChip, 'Absent').last);
    await t.pump();
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(repo.savedGrades.map((g) => (g.enrollmentId, g.value, g.absent)), [(10, '14.5', false), (11, null, true)]);
  });

  testWidgets('report card shows subjects with coefficients, rank, honour, conduct and absences', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ReportCardPage(enrollmentId: 10, period: 1), me: meWith('director')));
    await t.pumpAndSettle();
    expect(find.text('Mathématiques'), findsOneWidget);
    expect(find.text('16.00'), findsWidgets);
    expect(find.text('1er sur 3'), findsOneWidget);
    expect(find.text('Félicitations'), findsOneWidget);
    expect(find.text('17.50'), findsOneWidget);
    expect(find.textContaining('1 abs. non justifiée'), findsOneWidget);
    expect(find.textContaining('Élève sérieuse'), findsOneWidget);
    expect(find.text('Conduite, appréciation, décision'), findsOneWidget);
    expect(reportCardText(await FakeRepo().reportCard(10, 1)), contains('Rang : 1er sur 3'));
  });

  testWidgets('reminders: a WhatsApp reminder, a call-only family, the hours warning, promise and mark-sent', (t) async {
    phone(t, h: 2400);
    final repo = FakeRepo()
      ..reminderItems.addAll(const [
        ReminderItem(id: 1, familyId: 5, familyName: 'KOUASSI', step: 'late_3', channel: 'whatsapp', amount: 200000, text: 'Bonjour Kouassi Paul, sauf erreur de notre part…', canSendNow: false, contactName: 'Kouassi Paul', phone: '+2250701020304', waLink: 'https://wa.me/2250701020304?text=x'),
        ReminderItem(id: 2, familyId: 6, familyName: 'BAMBA', step: 'late_10', channel: 'appel', amount: 85000, text: 'Il reste 85 000 FCFA', canSendNow: false, contactName: 'Bamba Issa', phone: '+2250505050505'),
      ]);
    await t.pumpWidget(harness(const RemindersPage(), me: meWith('accountant'), repo: repo));
    await t.pumpAndSettle();
    expect(find.textContaining('Hors des heures d'), findsOneWidget);
    expect(find.text('Envoyer sur WhatsApp'), findsOneWidget); // only the opted-in family
    expect(find.text('Appeler'), findsOneWidget);
    expect(find.text('À appeler'), findsOneWidget);
    expect(find.text('Premier retard'), findsOneWidget);
    await t.tap(find.text('Marquer comme envoyé').first);
    await t.pumpAndSettle();
    expect(repo.sentReminders, [1]);
    await t.tap(find.text('Promesse de paiement').first);
    await t.pumpAndSettle();
    expect(find.text('Indiquez le montant et la date promise.'), findsNothing);
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(find.text('Indiquez le montant et la date promise.'), findsOneWidget); // no date chosen: refused
    expect(repo.promises, isEmpty);
  });

  testWidgets('reminders: nothing to send shows the empty state', (t) async {
    phone(t);
    await t.pumpWidget(harness(const RemindersPage(), me: meWith('accountant')));
    await t.pumpAndSettle();
    expect(find.text("Aucune relance à envoyer aujourd'hui."), findsOneWidget);
  });

  testWidgets('subjects and coefficients per level', (t) async {
    phone(t);
    await t.pumpWidget(harness(const SubjectsPage(), me: meWith('director')));
    await t.pumpAndSettle();
    await t.tap(find.text('6e'));
    await t.pumpAndSettle();
    expect(find.text('Mathématiques'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await t.tap(find.byTooltip('Plus').first);
    await t.pump();
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget); // appears only when something changed
  });

  testWidgets('grades home lists the classes of the year', (t) async {
    phone(t);
    await t.pumpWidget(harness(const GradesPage(), me: meWith('teacher')));
    await t.pumpAndSettle();
    expect(find.text('6e 1'), findsOneWidget);
    expect(find.text('Niveau 6e'), findsOneWidget);
  });

  testWidgets('no overflow at 320 px, text x2: grade screens and reminders', (t) async {
    phone(t, h: 640, w: 320);
    final repo = FakeRepo()
      ..reminderItems.add(const ReminderItem(id: 1, familyId: 5, familyName: 'KOUASSI', step: 'late_3', channel: 'whatsapp', amount: 200000, text: 'Bonjour', canSendNow: true, contactName: 'Kouassi Paul', phone: '+2250701020304', waLink: 'x'));
    final problems = <String>[];
    for (final page in <Widget>[
      const GradesPage(),
      const ClassPage(classroomId: 1, name: '6e 1', level: '6e'),
      const GradeEntryPage(evaluationId: 7),
      const ReportCardPage(enrollmentId: 10, period: 1),
      const RemindersPage(),
      const SubjectsPage(),
    ]) {
      await t.pumpWidget(harness(page, me: meWith('director'), repo: repo, textScale: 2.0));
      await t.pumpAndSettle();
      final e = t.takeException();
      if (e != null) problems.add('${page.runtimeType}: ${e.toString().split('\n').first}');
    }
    expect(problems, isEmpty);
  });
}
