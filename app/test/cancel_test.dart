import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/errors.dart';
import 'package:scolaris/core/models.dart';
import 'package:scolaris/features/grades/grades_page.dart';
import 'package:scolaris/features/timetable/timetable_pages.dart';

import 'helpers.dart';

void main() {
  void phone(WidgetTester t, {double h = 2400, double w = 390}) => t.view
    ..physicalSize = Size(w, h)
    ..devicePixelRatio = 1.0;

  final monday = DateTime(2026, 10, 5, 9, 30); // 09:30: the 08:00 period is over, the 10:00 one is ahead

  // Prof Math (id 3): one period already over, one ahead
  const over = Slot(id: 1, classroomId: 1, classroom: '6e 1', weekday: 1, start: '08:00', end: '09:00', subjectId: 1, subject: 'Mathématiques', teacherId: 3, teacher: 'Prof Math');
  const ahead = Slot(id: 2, classroomId: 1, classroom: '6e 1', weekday: 1, start: '10:00', end: '11:00', subjectId: 2, subject: 'Français', teacherId: 3, teacher: 'Prof Math');
  const colleague = Slot(id: 3, classroomId: 1, classroom: '6e 1', weekday: 1, start: '11:00', end: '12:00', subjectId: 2, subject: 'Histoire', teacherId: 4, teacher: 'Prof Francais');

  FakeRepo repo0({List<Slot> slots = const [over, ahead], List<Cancellation> cancelled = const []}) {
    final r = FakeRepo();
    r.timetable = ClassTimetable(editable: true, slots: slots, teachers: r.timetable.teachers, cancellations: cancelled);
    r.cancellations = cancelled;
    return r;
  }

  testWidgets('a teacher can cancel a session that is still ahead, not one that is over', (t) async {
    phone(t);
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('teacher', id: 3), repo: repo0()));
    await t.pumpAndSettle();
    expect(find.text('Annuler ce cours'), findsOneWidget); // only the 10:00 period
  });

  testWidgets('cancelling: summary, reason, note, then the exact request and a confirmation', (t) async {
    phone(t);
    final repo = repo0();
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('teacher', id: 3), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Annuler ce cours'));
    await t.pumpAndSettle();
    expect(find.text('Français · 6e 1'), findsWidgets);
    expect(find.text('Lundi 05/10/2026 · 10:00-11:00'), findsOneWidget);
    for (final r in ['Maladie', 'Absence autorisée', 'Formation', 'Autre']) {
      expect(find.widgetWithText(ChoiceChip, r), findsOneWidget, reason: r);
    }
    expect(find.textContaining('sans le motif'), findsOneWidget); // she is told what the families will see
    await t.enterText(find.byType(TextField), 'Grippe');
    await t.tap(find.widgetWithText(FilledButton, 'Annuler ce cours'));
    await t.pumpAndSettle();
    expect(repo.cancelledCalls.single, (slotId: 2, date: DateTime(2026, 10, 5), reason: 'maladie', note: 'Grippe'));
    expect(find.text("Cours annulé. L'administration est prévenue."), findsOneWidget);
  });

  testWidgets('"Autre" needs an explanation: nothing is sent without one', (t) async {
    phone(t);
    final repo = repo0();
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('teacher', id: 3), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Annuler ce cours'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Autre'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Annuler ce cours'));
    await t.pumpAndSettle();
    expect(find.text('Précisez le motif'), findsOneWidget);
    expect(repo.cancelledCalls, isEmpty);
  });

  testWidgets('a refusal from the server is shown in words, and the session is not cancelled', (t) async {
    phone(t);
    final repo = repo0()..cancelError = AppError('course_already_over', status: 400, message: 'Ce cours est déjà terminé.');
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('teacher', id: 3), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Annuler ce cours'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Annuler ce cours'));
    await t.pumpAndSettle();
    expect(find.text('Ce cours est déjà terminé.'), findsOneWidget);
    expect(repo.cancelledCalls, isEmpty);
  });

  testWidgets('a cancelled session is struck through with its reason (for her), and can be restored after a confirmation', (t) async {
    phone(t);
    final repo = repo0(cancelled: [Cancellation(slotId: 2, date: DateTime(2026, 10, 5), reason: 'maladie', note: 'Grippe')]);
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('teacher', id: 3), repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Cours annulé'), findsOneWidget);
    expect(find.text('Maladie'), findsOneWidget);
    expect(find.text('Grippe'), findsOneWidget);
    expect(find.text('Annuler ce cours'), findsNothing); // already cancelled
    final title = t.widget<Text>(find.text('Français · 6e 1'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
    await t.tap(find.text('Rétablir'));
    await t.pumpAndSettle();
    expect(find.text('Rétablir ce cours ?'), findsOneWidget);
    await t.tap(find.text('Annuler')); // changed her mind about restoring
    await t.pumpAndSettle();
    expect(repo.restoredCalls, isEmpty);
    await t.tap(find.text('Rétablir'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Rétablir').last);
    await t.pumpAndSettle();
    expect(repo.restoredCalls.single, (slotId: 2, date: DateTime(2026, 10, 5)));
  });

  testWidgets('next week has its own dates and its own cancellations', (t) async {
    phone(t);
    final repo = repo0(cancelled: [Cancellation(slotId: 2, date: DateTime(2026, 10, 12), reason: 'formation')]);
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('teacher', id: 3), repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Lundi 05/10/2026'), findsOneWidget);
    expect(find.text('Cours annulé'), findsNothing); // this week is untouched
    await t.tap(find.text('Semaine prochaine'));
    await t.pumpAndSettle();
    expect(find.text('Lundi 12/10/2026'), findsOneWidget);
    expect(find.text('Cours annulé'), findsOneWidget);
    expect(find.text('Formation'), findsOneWidget);
    expect(find.text('En cours'), findsNothing); // never "in progress" on a future date
  });

  testWidgets('a teacher cancels her own periods only; the director and secretary any', (t) async {
    phone(t);
    final early = DateTime(2026, 10, 5, 6, 0);
    final repo = repo0(slots: const [ahead, colleague]);
    Future<void> as(String role, int id) async {
      await t.pumpWidget(harness(ClassTimetableTab(classroomId: 1, now: early), me: meWith(role, id: id), repo: repo));
      await t.pumpAndSettle();
    }

    await as('teacher', 3);
    expect(find.text('Annuler ce cours'), findsOneWidget);
    await as('director', 1);
    expect(find.text('Annuler ce cours'), findsNWidgets(2));
    await as('secretary', 2);
    expect(find.text('Annuler ce cours'), findsNWidgets(2));
  });

  testWidgets('parents see "Cours annulé" but never the reason, and cannot act', (t) async {
    phone(t);
    final repo = repo0(cancelled: [Cancellation(slotId: 2, date: DateTime(2026, 10, 5))]); // the server sends no reason to parents
    await t.pumpWidget(harness(ChildTimetablePage(enrollmentId: 10, name: 'Fanta TRAORE', now: monday), me: null, repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Cours annulé'), findsOneWidget);
    for (final reason in ['Maladie', 'Formation', 'Absence autorisée']) {
      expect(find.text(reason), findsNothing);
    }
    expect(find.text('Annuler ce cours'), findsNothing);
    expect(find.text('Rétablir'), findsNothing);
  });

  CancelledSession session({String reason = 'maladie', String? note = 'Grippe'}) => CancelledSession(
        slotId: 2, date: DateTime(2026, 10, 5), start: '10:00', end: '11:00', classroom: '6e 1', subject: 'Français', teacher: 'Prof Math', reason: reason, note: note,
        message: 'Le cours de Français de la 6e 1 du lundi 05/10 (10:00-11:00) est annulé (enseignant absent). Merci de votre compréhension.',
      );

  testWidgets('the administration lists the cancelled courses and copies the message for the families', (t) async {
    phone(t);
    final copied = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final repo = FakeRepo()..upcoming = [session()];
    await t.pumpWidget(harness(const CancelledCoursesPage(), me: meWith('director'), repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Français · 6e 1'), findsOneWidget);
    expect(find.text('Lundi 05/10/2026 · 10:00-11:00 · Prof Math'), findsOneWidget);
    expect(find.text('Maladie'), findsOneWidget); // the administration sees the real reason
    expect(find.text('Grippe'), findsOneWidget);
    await t.tap(find.text('Copier le message aux familles'));
    await t.pumpAndSettle();
    expect(copied.single, contains('enseignant absent'));
    expect(copied.single, isNot(contains('maladie')));
    expect(copied.single, isNot(contains('Grippe')));
    await t.tap(find.text('Rétablir'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Rétablir').last);
    await t.pumpAndSettle();
    expect(repo.restoredCalls.single, (slotId: 2, date: DateTime(2026, 10, 5)));
  });

  testWidgets('no cancelled course: a clear empty state', (t) async {
    phone(t);
    await t.pumpWidget(harness(const CancelledCoursesPage(), me: meWith('secretary')));
    await t.pumpAndSettle();
    expect(find.text('Aucun cours annulé à venir.'), findsOneWidget);
  });

  testWidgets('the cancelled-courses shortcut is for the administration only', (t) async {
    phone(t);
    for (final (role, visible) in const [('director', true), ('secretary', true), ('teacher', false)]) {
      await t.pumpWidget(harness(const GradesPage(), me: meWith(role)));
      await t.pumpAndSettle();
      expect(find.byTooltip('Cours annulés'), visible ? findsOneWidget : findsNothing, reason: role);
    }
  });

  test('server sentences for dates are kept; each code has a fallback; payments keep their own message', () {
    AppError e(String code, [String? message]) => AppError(code, status: 400, message: message);
    expect(userMessage(e('date_not_that_weekday', 'Ce cours a lieu le lundi.')), 'Ce cours a lieu le lundi.');
    expect(userMessage(e('date_in_the_past')), 'Cette date est passée.');
    expect(userMessage(e('outside_school_year')), contains("année scolaire"));
    expect(userMessage(e('session_already_cancelled')), 'Cette séance est déjà annulée.');
    expect(userMessage(e('already_cancelled')), 'Ce paiement est déjà annulé.');
    expect(userMessage(e('not_your_course')), contains('vos propres cours'));
    expect(Cancellation.fromJson(const {'slot_id': 2, 'date': '2026-10-05'}).reason, isNull);
  });

  testWidgets('no overflow at 320 px, text x2: cancel sheet, cancelled courses, a week with cancellations', (t) async {
    phone(t, h: 640, w: 320);
    final problems = <String>[];
    final repo = repo0(cancelled: [Cancellation(slotId: 2, date: DateTime(2026, 10, 5), reason: 'absence_autorisee', note: 'Réunion avec le rectorat de Bouaké')])..upcoming = [session(reason: 'absence_autorisee')];
    for (final page in <Widget>[MyWeekPage(now: monday), const CancelledCoursesPage(), ClassTimetableTab(classroomId: 1, now: monday)]) {
      await t.pumpWidget(harness(page, me: meWith('director'), repo: repo, textScale: 2.0));
      await t.pumpAndSettle();
      final ex = t.takeException();
      if (ex != null) problems.add('${page.runtimeType}: ${ex.toString().split('\n').first}');
    }
    phone(t, h: 2400, w: 320); // tall enough to build the lazy list; the width and the text scale are what is being checked
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('teacher', id: 3), repo: repo0(), textScale: 2.0));
    await t.pumpAndSettle();
    await t.tap(find.text('Annuler ce cours'));
    await t.pumpAndSettle();
    final ex = t.takeException();
    if (ex != null) problems.add('CancelSheet: ${ex.toString().split('\n').first}');
    expect(problems, isEmpty);
  });
}
