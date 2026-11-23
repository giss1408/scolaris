import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/models.dart';
import 'package:scolaris/features/grades/class_page.dart';
import 'package:scolaris/features/grades/grades_page.dart';
import 'package:scolaris/features/grades/report_card_page.dart';
import 'package:scolaris/features/setup/class_teachers_page.dart';
import 'package:scolaris/features/setup/classes_page.dart';

import 'helpers.dart';

void main() {
  void phone(WidgetTester t, {double h = 2000, double w = 390}) => t.view
    ..physicalSize = Size(w, h)
    ..devicePixelRatio = 1.0;

  testWidgets('a teacher with no class sees why and what to do', (t) async {
    phone(t);
    await t.pumpWidget(harness(const GradesPage(), me: meWith('teacher'), repo: FakeRepo()..rooms = const []));
    await t.pumpAndSettle();
    expect(find.textContaining('Aucune classe ne vous est attribuée'), findsOneWidget);
    expect(find.textContaining('Demandez au directeur'), findsOneWidget);
  });

  testWidgets('the head teacher is marked on her class', (t) async {
    phone(t);
    await t.pumpWidget(harness(const GradesPage(), me: meWith('teacher'), repo: FakeRepo()..rooms = const [Classroom(id: 1, name: '6e 1', level: '6e', isHead: true), Classroom(id: 2, name: '6e 2', level: '6e')]));
    await t.pumpAndSettle();
    expect(find.text('Professeur principal'), findsOneWidget);
    expect(find.text('6e 2'), findsOneWidget);
  });

  testWidgets('a new evaluation offers only the subjects she gives in the class', (t) async {
    phone(t, h: 2400);
    await t.pumpWidget(harness(const ClassPage(classroomId: 1, name: '6e 1', level: '6e'), me: meWith('teacher'), repo: FakeRepo()..mySubjectIds = {1}));
    await t.pumpAndSettle();
    await t.tap(find.text('Nouvelle évaluation'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Mathématiques'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Français'), findsNothing);
  });

  testWidgets('no subject given in the class: she is told so instead of an empty form', (t) async {
    phone(t, h: 2400);
    await t.pumpWidget(harness(const ClassPage(classroomId: 1, name: '6e 1', level: '6e'), me: meWith('teacher'), repo: FakeRepo()..mySubjectIds = <int>{}));
    await t.pumpAndSettle();
    await t.tap(find.text('Nouvelle évaluation'));
    await t.pumpAndSettle();
    expect(find.text('Aucune matière ne vous est attribuée dans cette classe.'), findsOneWidget);
  });

  testWidgets('conduct and appreciation: head teacher yes, other teacher no, director and secretary yes', (t) async {
    phone(t);
    const edit = 'Conduite, appréciation, décision';
    await t.pumpWidget(harness(const ReportCardPage(enrollmentId: 10, period: 1), me: meWith('teacher'), repo: FakeRepo()..rooms = const [Classroom(id: 1, name: '6e 1', level: '6e')]));
    await t.pumpAndSettle();
    expect(find.text(edit), findsNothing);
    await t.pumpWidget(harness(const ReportCardPage(enrollmentId: 10, period: 1), me: meWith('teacher'), repo: FakeRepo()..rooms = const [Classroom(id: 1, name: '6e 1', level: '6e', isHead: true)]));
    await t.pumpAndSettle();
    expect(find.text(edit), findsOneWidget);
    for (final role in ['director', 'secretary']) {
      await t.pumpWidget(harness(const ReportCardPage(enrollmentId: 10, period: 1), me: meWith(role)));
      await t.pumpAndSettle();
      expect(find.text(edit), findsOneWidget, reason: role);
    }
  });

  testWidgets('the director opens a class from the list to assign its teachers', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ClassesPage(), me: meWith('director')));
    await t.pumpAndSettle();
    expect(find.textContaining('Enseignants de la classe'), findsOneWidget);
  });

  testWidgets('assign: shows the current teachers, adds one on all subjects, names a head teacher, saves the exact payload', (t) async {
    phone(t, h: 2400);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const ClassTeachersPage(classroomId: 1, name: '6e 1'), me: meWith('director'), repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Prof Math'), findsWidgets);
    expect(find.text('Mathématiques'), findsOneWidget);
    expect(find.text('Enregistrer'), findsNothing); // nothing changed yet
    await t.tap(find.text('Affecter un enseignant'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Prof Francais').last);
    await t.tap(find.widgetWithText(ChoiceChip, 'Toutes les matières'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Affecter un enseignant'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Prof Francais').first); // head teacher chip
    await t.pump();
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(repo.savedTeachers!.head, 4);
    expect(repo.savedTeachers!.list.map((a) => (a.staffId, a.subjectId)), [(3, 1), (4, null)]);
  });

  testWidgets('assign: with no teacher in the team, the director is sent to add some', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ClassTeachersPage(classroomId: 1, name: '6e 1'), me: meWith('director'), repo: FakeRepo()..staffRows = const [StaffRow(id: 1, name: 'Awa Koné', role: 'director', active: true)]));
    await t.pumpAndSettle();
    expect(find.textContaining("Aucun enseignant dans l'équipe"), findsOneWidget);
  });

  testWidgets('no overflow at 320 px, text x2: assignments', (t) async {
    phone(t, h: 640, w: 320);
    final problems = <String>[];
    for (final page in <Widget>[const ClassTeachersPage(classroomId: 1, name: '6e 1'), const ClassesPage(), const GradesPage()]) {
      await t.pumpWidget(harness(page, me: meWith('director'), textScale: 2.0));
      await t.pumpAndSettle();
      final e = t.takeException();
      if (e != null) problems.add('${page.runtimeType}: ${e.toString().split('\n').first}');
    }
    expect(problems, isEmpty);
  });
}
