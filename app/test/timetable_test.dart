import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/errors.dart';
import 'package:scolaris/core/models.dart';
import 'package:scolaris/features/grades/class_page.dart';
import 'package:scolaris/features/home/shell_page.dart';
import 'package:scolaris/features/parent/parent_pages.dart';
import 'package:scolaris/features/timetable/timetable_pages.dart';
import 'package:scolaris/features/timetable/week_view.dart';

import 'helpers.dart';

void main() {
  void phone(WidgetTester t, {double h = 2000, double w = 390}) => t.view
    ..physicalSize = Size(w, h)
    ..devicePixelRatio = 1.0;

  final monday = DateTime(2026, 10, 5, 8, 30); // a Monday, in the middle of the first period
  // Monday only: the week-view tests pick the day themselves
  const slots = [
    Slot(id: 1, classroomId: 1, classroom: '6e 1', weekday: 1, start: '08:00', end: '09:00', subjectId: 1, subject: 'Mathématiques', teacherId: 3, teacher: 'Prof Math', room: 'A1'),
    Slot(id: 2, classroomId: 1, classroom: '6e 1', weekday: 1, start: '10:00', end: '11:00', subjectId: 2, subject: 'Français', teacherId: 4, teacher: 'Prof Francais'),
  ];

  Widget week({DateTime? now, List<Slot>? data, bool teacher = true, void Function(Slot)? onDelete}) =>
      Scaffold(body: WeekView(slots: data ?? slots, now: now ?? monday, showTeacher: teacher, onDelete: onDelete));

  testWidgets('the week opens on today, shows the period in progress and the next one', (t) async {
    phone(t);
    await t.pumpWidget(harness(week(), me: meWith('director')));
    await t.pumpAndSettle();
    expect(find.text('Mathématiques'), findsOneWidget);
    expect(find.text('Prof Math · Salle A1'), findsOneWidget);
    expect(find.text('En cours'), findsOneWidget); // 08:30 is inside 08:00-09:00
    expect(find.text('Prochain'), findsOneWidget); // 10:00 comes next
    expect(find.text('Prof Francais · Salle A1'), findsNothing);
    expect(find.text('Prof Francais'), findsOneWidget);
  });

  testWidgets('another day, an empty day, and no badge off today', (t) async {
    phone(t);
    await t.pumpWidget(harness(week(), me: meWith('director')));
    await t.pumpAndSettle();
    await t.tap(find.text('Mar'));
    await t.pumpAndSettle();
    expect(find.text('Pas de cours ce jour.'), findsOneWidget);
    await t.tap(find.text('Lun'));
    await t.pumpAndSettle();
    expect(find.text('En cours'), findsOneWidget);
    // the same Monday periods, seen on a Wednesday: no live badge
    await t.pumpWidget(harness(week(now: DateTime(2026, 10, 7, 8, 30)), me: meWith('director')));
    await t.pumpAndSettle();
    await t.tap(find.text('Lun'));
    await t.pumpAndSettle();
    expect(find.text('En cours'), findsNothing);
    expect(find.text('Prochain'), findsNothing);
  });

  testWidgets('Sunday opens on Monday; an empty timetable says so', (t) async {
    phone(t);
    await t.pumpWidget(harness(week(now: DateTime(2026, 10, 11, 9)), me: meWith('director')));
    await t.pumpAndSettle();
    expect(find.text('Mathématiques'), findsOneWidget);
    await t.pumpWidget(harness(week(data: const []), me: meWith('director')));
    await t.pumpAndSettle();
    expect(find.text("Aucun cours n'est encore planifié."), findsOneWidget);
  });

  testWidgets('a period without a teacher is shown as such', (t) async {
    phone(t);
    const lone = <Slot>[Slot(id: 9, classroomId: 1, classroom: '6e 1', weekday: 1, start: '07:00', end: '08:00', subjectId: 3, subject: 'EPS')];
    await t.pumpWidget(harness(week(data: lone), me: meWith('director')));
    await t.pumpAndSettle();
    expect(find.text('Sans enseignant'), findsOneWidget);
  });

  testWidgets('class timetable tab: the director can add a period; only the teachers of that subject are offered', (t) async {
    phone(t, h: 2600);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const ClassPage(classroomId: 1, name: '6e 1', level: '6e'), me: meWith('director'), repo: repo));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Horaires')); // the tab bar scrolls
    await t.tap(find.text('Horaires'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ajouter un cours'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Mer').last); // the sheet's chip, not the week view's behind it
    await t.tap(find.widgetWithText(ChoiceChip, 'Mathématiques').last);
    await t.pump();
    expect(find.widgetWithText(ChoiceChip, 'Prof Math'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Prof Francais'), findsNothing); // gives French only
    await t.tap(find.widgetWithText(ChoiceChip, 'Prof Math'));
    await t.enterText(find.byType(TextField).last, 'B2');
    await t.tap(find.widgetWithText(FilledButton, 'Ajouter un cours'));
    await t.pumpAndSettle();
    expect(repo.addedSlots.single, (weekday: 3, start: '08:00', end: '09:00', subjectId: 1, teacherId: 3, room: 'B2'));
  });

  testWidgets('a clash is shown with the server sentence, and nothing is added', (t) async {
    phone(t, h: 2600);
    final repo = FakeRepo()..addSlotError = AppError('room_busy', status: 409, message: 'La salle A1 est déjà prise par la 6e 2 de 08:00 à 09:00.');
    await t.pumpWidget(harness(const ClassPage(classroomId: 1, name: '6e 1', level: '6e'), me: meWith('director'), repo: repo));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Horaires')); // the tab bar scrolls
    await t.tap(find.text('Horaires'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ajouter un cours'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Mathématiques').last);
    await t.tap(find.widgetWithText(FilledButton, 'Ajouter un cours'));
    await t.pumpAndSettle();
    expect(find.text('La salle A1 est déjà prise par la 6e 2 de 08:00 à 09:00.'), findsOneWidget);
    expect(repo.addedSlots, isEmpty);
  });

  testWidgets('adding without a subject is refused in the form', (t) async {
    phone(t, h: 2600);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const ClassPage(classroomId: 1, name: '6e 1', level: '6e'), me: meWith('director'), repo: repo));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Horaires')); // the tab bar scrolls
    await t.tap(find.text('Horaires'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ajouter un cours'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Ajouter un cours'));
    await t.pumpAndSettle();
    expect(find.text('Choisissez une matière'), findsOneWidget);
    expect(repo.addedSlots, isEmpty);
  });

  testWidgets('deleting a period asks first', (t) async {
    phone(t);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const ClassPage(classroomId: 1, name: '6e 1', level: '6e'), me: meWith('secretary'), repo: repo));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Horaires')); // the tab bar scrolls
    await t.tap(find.text('Horaires'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Retirer').first);
    await t.pumpAndSettle();
    expect(find.text('Supprimer ce cours ?'), findsOneWidget);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(repo.deletedSlots, isEmpty);
    await t.tap(find.byTooltip('Retirer').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Retirer').last);
    await t.pumpAndSettle();
    expect(repo.deletedSlots, hasLength(1)); // the one confirmed, not the one cancelled
  });

  testWidgets('a teacher reads the class timetable but cannot edit it', (t) async {
    phone(t);
    final repo = FakeRepo();
    repo.timetable = ClassTimetable(editable: false, slots: repo.timetable.slots);
    await t.pumpWidget(harness(const ClassPage(classroomId: 1, name: '6e 1', level: '6e'), me: meWith('teacher'), repo: repo));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Horaires')); // the tab bar scrolls
    await t.tap(find.text('Horaires'));
    await t.pumpAndSettle();
    expect(find.text('Mathématiques'), findsOneWidget);
    expect(find.text('Ajouter un cours'), findsNothing);
    expect(find.byTooltip('Retirer'), findsNothing);
  });

  testWidgets('a teacher has a Horaires tab with her week, class by class', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ShellPage(), me: meWith('teacher')));
    await t.pumpAndSettle();
    final bar = find.byType(NavigationBar);
    for (final l in ['Notes', 'Horaires', 'Profil']) {
      expect(find.descendant(of: bar, matching: find.text(l)), findsOneWidget, reason: l);
    }
    await t.tap(find.descendant(of: bar, matching: find.text('Horaires')));
    await t.pumpAndSettle();
    expect(find.text('Mon emploi du temps'), findsOneWidget);
    expect(find.text('Mathématiques · 6e 1'), findsWidgets);
    for (final role in ['director', 'secretary', 'accountant']) {
      await t.pumpWidget(harness(const ShellPage(), me: meWith(role)));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Horaires')), findsNothing, reason: role);
    }
  });

  testWidgets('a parent opens the timetable of her child from the child page', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ChildPage(enrollmentId: 10, name: 'Fanta TRAORE'), me: null));
    await t.pumpAndSettle();
    expect(find.text('Emploi du temps'), findsOneWidget);
    await t.pumpWidget(harness(ChildTimetablePage(enrollmentId: 10, name: 'Fanta TRAORE', now: monday), me: null));
    await t.pumpAndSettle();
    expect(find.text('Mathématiques'), findsOneWidget);
    expect(find.text('Prof Math · Salle A1'), findsOneWidget);
    expect(find.byTooltip('Retirer'), findsNothing);
  });

  test('scheduling conflicts keep the server sentence; other codes have a fallback', () {
    DioException clash(String code, String? message) => DioException(
        requestOptions: RequestOptions(path: '/x'), response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: 409, data: {'detail': code, if (message != null) 'message': message}));
    expect(userMessage(clash('teacher_busy', "L'enseignant(e) est déjà en 6e 2 de 09:00 à 10:00.")), "L'enseignant(e) est déjà en 6e 2 de 09:00 à 10:00.");
    expect(userMessage(clash('teacher_busy', null)), contains('déjà un cours'));
    expect(userMessage(clash('room_busy', null)), contains('salle'));
    expect(Slot.fromJson(const {'id': 1, 'classroom_id': 1, 'classroom': 'A', 'weekday': 1, 'start': '07:30', 'end': '09:05', 'subject_id': 1, 'subject': 'X'}).endMinutes, 9 * 60 + 5);
  });

  testWidgets('no overflow at 320 px, text x2: timetable screens', (t) async {
    phone(t, h: 640, w: 320);
    final problems = <String>[];
    for (final page in <Widget>[
      const ClassPage(classroomId: 1, name: '6e 1', level: '6e'),
      const MyWeekPage(),
      const ChildTimetablePage(enrollmentId: 10, name: 'Fanta TRAORE'),
      const ChildPage(enrollmentId: 10, name: 'Fanta TRAORE'),
    ]) {
      await t.pumpWidget(harness(page, me: meWith('director'), textScale: 2.0));
      await t.pumpAndSettle();
      final e = t.takeException();
      if (e != null) problems.add('${page.runtimeType}: ${e.toString().split('\n').first}');
    }
    expect(problems, isEmpty);
  });
}
