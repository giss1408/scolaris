import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/errors.dart';
import 'package:scolaris/core/models.dart';
import 'package:scolaris/core/school_logo.dart';
import 'package:scolaris/features/attendance/course_roll_page.dart';
import 'package:scolaris/features/home/profile_page.dart';
import 'package:scolaris/features/messages/messages_page.dart';
import 'package:scolaris/features/parent/parent_pages.dart';
import 'package:scolaris/features/parent/report_sheet.dart';
import 'package:scolaris/features/setup/logo_sheet.dart';
import 'package:scolaris/features/timetable/timetable_pages.dart';
import 'package:scolaris/features/timetable/week_view.dart';

import 'helpers.dart';

// a valid 1x1 transparent PNG
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  void phone(WidgetTester t, {double h = 2400, double w = 390}) => t.view
    ..physicalSize = Size(w, h)
    ..devicePixelRatio = 1.0;

  final monday = DateTime(2026, 10, 5, 9, 30);
  const started = Slot(id: 1, classroomId: 1, classroom: '6e 1', weekday: 1, start: '08:00', end: '09:00', subjectId: 1, subject: 'Mathématiques', teacherId: 3, teacher: 'Prof Math');
  const ahead = Slot(id: 2, classroomId: 1, classroom: '6e 1', weekday: 1, start: '10:00', end: '11:00', subjectId: 2, subject: 'Français', teacherId: 3, teacher: 'Prof Math');

  FakeRepo withSlots(List<Slot> slots, {List<Cancellation> cancelled = const []}) {
    final r = FakeRepo();
    r.timetable = ClassTimetable(editable: true, slots: slots, teachers: r.timetable.teachers, cancellations: cancelled);
    r.cancellations = cancelled;
    return r;
  }

  testWidgets('the roll button appears for a course that has started, not for one still ahead', (t) async {
    phone(t);
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('teacher', id: 3), repo: withSlots([started, ahead])));
    await t.pumpAndSettle();
    expect(find.text("Faire l'appel"), findsOneWidget); // only the 08:00 course, it is 09:30
  });

  testWidgets('no roll for a cancelled session; the replacement gets one on her day, with a Remplacement badge', (t) async {
    phone(t);
    final cancelled = [Cancellation(slotId: 1, date: DateTime(2026, 10, 5), reason: 'maladie')];
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('teacher', id: 3), repo: withSlots(const [started], cancelled: cancelled)));
    await t.pumpAndSettle();
    expect(find.text("Faire l'appel"), findsNothing);
    // Prof Francais covers Prof Math's cancelled 08:00 session
    final repo = FakeRepo()
      ..timetable = const ClassTimetable(editable: false, slots: [])
      ..cancellations = const [];
    await t.pumpWidget(harness(
      Scaffold(body: WeekView(slots: const [], substitutions: [(slot: started, date: DateTime(2026, 10, 5))], showClass: true, showTeacher: false, now: monday, onRoll: (_, __) {}, canCancel: (_) => false)),
      me: meWith('teacher', id: 4),
      repo: repo,
    ));
    await t.pumpAndSettle();
    expect(find.text('Remplacement'), findsOneWidget);
    expect(find.text("Faire l'appel"), findsOneWidget);
    expect(find.text('Annuler ce cours'), findsNothing); // she cannot cancel a course that is not hers
  });

  testWidgets('course roll: reports and all-day absences are shown, marks are saved exactly, the parents told count is displayed', (t) async {
    phone(t);
    final repo = FakeRepo()..rollNotified = 2;
    await t.pumpWidget(harness(CourseRollPage(slot: started, date: DateTime(2026, 10, 5)), me: meWith('teacher', id: 3), repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Signalée par les parents : Maladie'), findsOneWidget);
    expect(find.text('Absent toute la journée'), findsOneWidget);
    expect(find.text('Mathématiques · 6e 1 · 05/10/2026 · 08:00-09:00'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, 'Absent').first);
    await t.pump();
    await t.tap(find.widgetWithText(ChoiceChip, 'Retard').at(1));
    await t.pump();
    await t.tap(find.widgetWithText(FilterChip, 'Justifié').last);
    await t.pump();
    expect(find.text('1 absent(s) · 1 en retard'), findsOneWidget);
    await t.tap(find.text("Enregistrer l'appel"));
    await t.pumpAndSettle();
    final saved = repo.savedRolls.single;
    expect(saved.slotId, 1);
    expect(saved.entries.map((e) => (e.enrollmentId, e.kind, e.justified)), [(10, 'absence', false), (11, 'retard', true)]);
  });

  testWidgets('course roll: a pupil set back to Présent is not sent', (t) async {
    phone(t);
    final repo = FakeRepo();
    await t.pumpWidget(harness(CourseRollPage(slot: started, date: DateTime(2026, 10, 5)), me: meWith('teacher', id: 3), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Absent').first);
    await t.pump();
    await t.tap(find.widgetWithText(ChoiceChip, 'Présent').first);
    await t.pump();
    await t.tap(find.text("Enregistrer l'appel"));
    await t.pumpAndSettle();
    expect(repo.savedRolls.single.entries, isEmpty);
  });

  testWidgets('a refused roll (not your course) shows the sentence and does not leave the page', (t) async {
    phone(t);
    final repo = _RefusingRoll();
    await t.pumpWidget(harness(CourseRollPage(slot: started, date: DateTime(2026, 10, 5)), me: meWith('teacher', id: 9), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text("Enregistrer l'appel"));
    await t.pumpAndSettle();
    expect(find.text("Vous pouvez faire l'appel d'aujourd'hui seulement."), findsOneWidget);
    expect(find.text('Appel du cours'), findsOneWidget);
  });

  testWidgets('the direction picks a replacement from a cancelled session, and sees who replaces', (t) async {
    phone(t, h: 2800);
    final cancelled = [Cancellation(slotId: 2, date: DateTime(2026, 10, 12), reason: 'maladie')];
    final repo = withSlots([ahead], cancelled: cancelled);
    await t.pumpWidget(harness(ClassTimetableTab(classroomId: 1, now: monday), me: meWith('director'), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Semaine prochaine'));
    await t.pumpAndSettle();
    await t.tap(find.text('Choisir un remplaçant'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, 'Prof Francais'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Prof Math'), findsNothing); // the absent teacher is not offered
    await t.tap(find.widgetWithText(ActionChip, 'Prof Francais'));
    await t.pumpAndSettle();
    expect(repo.substitutes.single, (slotId: 2, date: DateTime(2026, 10, 12), staffId: 4));
    // once named, everyone reading the timetable sees "Remplacé par"
    final named = withSlots([ahead], cancelled: [Cancellation(slotId: 2, date: DateTime(2026, 10, 12), substitute: 'Prof Francais', substituteId: 4)]); // the server sends parents no reason
    await t.pumpWidget(harness(ChildTimetablePage(enrollmentId: 10, name: 'Fanta TRAORE', now: monday), me: null, repo: named));
    await t.pumpAndSettle();
    await t.tap(find.text('Semaine prochaine'));
    await t.pumpAndSettle();
    expect(find.text('Remplacé par Prof Francais'), findsOneWidget);
    expect(find.text('Maladie'), findsNothing); // the parent sees the replacement, never the reason
  });

  testWidgets('cancelling: the direction may name a replacement at once; the absent teacher is not offered the choice', (t) async {
    phone(t, h: 2800);
    final repo = withSlots([ahead]);
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('director'), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Annuler ce cours'));
    await t.pumpAndSettle();
    expect(find.text('Remplaçant'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, 'Prof Francais'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Annuler ce cours'));
    await t.pumpAndSettle();
    expect(repo.cancelSubstitutes.single, 4);
    await t.pumpWidget(harness(MyWeekPage(now: monday), me: meWith('teacher', id: 3), repo: withSlots([ahead])));
    await t.pumpAndSettle();
    await t.tap(find.text('Annuler ce cours'));
    await t.pumpAndSettle();
    expect(find.text('Remplaçant'), findsNothing);
  });

  testWidgets('a parent reports an absence: payload, Sunday and "Autre" refused in the form, and she can withdraw one', (t) async {
    phone(t, h: 3000);
    final repo = FakeRepo()..myReports = [AbsenceReport(day: DateTime.now().add(const Duration(days: 2)), reason: 'rendez_vous', note: 'Dentiste')];
    await t.pumpWidget(harness(const ChildPage(enrollmentId: 10, name: 'Fanta TRAORE'), me: null, repo: repo));
    await t.pumpAndSettle();
    expect(find.text('ABSENCES SIGNALÉES'), findsOneWidget); // section headers are upper-cased
    expect(find.textContaining('Rendez-vous · Dentiste'), findsOneWidget);
    await t.tap(find.text('Retirer'));
    await t.pumpAndSettle();
    expect(repo.withdrawn, hasLength(1));
    await t.tap(find.text('Signaler une absence').first);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Autre'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Signaler une absence'));
    await t.pumpAndSettle();
    expect(find.text('Précisez le motif'), findsOneWidget);
    expect(repo.reported, isEmpty);
    await t.tap(find.widgetWithText(ChoiceChip, 'Maladie'));
    await t.pump();
    await t.enterText(find.byType(TextField).last, 'Palu');
    await t.tap(find.widgetWithText(FilledButton, 'Signaler une absence'));
    await t.pumpAndSettle();
    final r = repo.reported.single;
    expect((r.enrollmentId, r.reason, r.note), (10, 'maladie', 'Palu'));
    expect(find.text("L'école est prévenue."), findsOneWidget);
  });

  testWidgets('the report sheet refuses a Sunday', (t) async {
    phone(t, h: 2400);
    final repo = FakeRepo();
    final sunday = DateTime(2026, 11, 29, 9);
    await t.pumpWidget(harness(Scaffold(body: ReportSheet(enrollmentId: 10, childName: 'Fanta', today: sunday)), me: null, repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Signaler une absence'));
    await t.pumpAndSettle();
    expect(find.text("Il n'y a pas classe le dimanche."), findsOneWidget);
    expect(repo.reported, isEmpty);
  });

  testWidgets('absences a parent sees say whether they happened during a course', (t) async {
    phone(t, h: 3000);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const ChildPage(enrollmentId: 10, name: 'Fanta TRAORE'), me: null, repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Absence · 03/10/2026'), findsOneWidget);
  });

  testWidgets('a suspended school shows the parent a clear card and no balance', (t) async {
    phone(t);
    final repo = FakeRepo()..kids = const [ChildRow(enrollmentId: 10, name: 'Fanta TRAORE', school: 'Ecole A', classroom: '6e 1', year: '2026-2027', remaining: 0, overdue: 0, totalDue: 0, schoolId: 1, blocked: true)];
    await t.pumpWidget(harness(const ChildrenPage(), me: null, repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Service suspendu pour cet établissement'), findsOneWidget);
    expect(find.text("Contactez l'école."), findsOneWidget);
    expect(find.textContaining('Reste à payer'), findsNothing);
  });

  testWidgets('the school logo shows as an image, and as initials when there is none', (t) async {
    phone(t);
    final repo = FakeRepo()..logoBytes = _png;
    await t.pumpWidget(harness(const Scaffold(body: Center(child: SchoolLogo(name: 'Groupe Scolaire Les Palmiers', version: 'v1'))), me: null, repo: repo));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await t.pumpWidget(harness(const Scaffold(body: Center(child: SchoolLogo(name: 'Groupe Scolaire Les Palmiers'))), me: null, repo: FakeRepo()));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('GS'), findsOneWidget);
  });

  testWidgets('the director picks a logo: it is uploaded with its type, and the profile is refreshed', (t) async {
    phone(t);
    final session = FakeSession(meWith('director'));
    final repo = FakeRepo();
    await t.pumpWidget(ProviderScope(
      overrides: [sessionProvider2(session), repoOverride(repo), imagePickerProvider.overrideWithValue(() async => (bytes: _png, contentType: 'image/png'))],
      child: MaterialApp(home: harnessChild(const Scaffold(body: LogoSheet()))),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Choisir une image'));
    await t.pumpAndSettle();
    expect(repo.uploadedLogos.single, 'image/png:${_png.length}');
    expect(session.refreshes, 1);
  });

  testWidgets('a refused logo shows the reason and nothing changes; cancelling the picker does nothing', (t) async {
    phone(t);
    final session = FakeSession(meWith('director'));
    final repo = FakeRepo()..uploadError = AppError('image_too_large', status: 400);
    await t.pumpWidget(ProviderScope(
      overrides: [sessionProvider2(session), repoOverride(repo), imagePickerProvider.overrideWithValue(() async => (bytes: _png, contentType: 'image/png'))],
      child: MaterialApp(home: harnessChild(const Scaffold(body: LogoSheet()))),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Choisir une image'));
    await t.pumpAndSettle();
    expect(find.text("L'image est trop lourde (512 Ko maximum)."), findsOneWidget);
    expect(session.refreshes, 0);
    final none = FakeRepo();
    await t.pumpWidget(ProviderScope(
      overrides: [sessionProvider2(FakeSession(meWith('director'))), repoOverride(none), imagePickerProvider.overrideWithValue(() async => null)],
      child: MaterialApp(home: harnessChild(const Scaffold(body: LogoSheet()))),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Choisir une image'));
    await t.pumpAndSettle();
    expect(none.uploadedLogos, isEmpty);
  });

  testWidgets('profile: logo row and the automatic WhatsApp switch are for the director; the log is for the others too', (t) async {
    phone(t, h: 3000);
    final repo = FakeRepo();
    final session = FakeSession(meWith('director'));
    await t.pumpWidget(harness(const ProfilePage(), me: null, session: session, repo: repo));
    await t.pumpAndSettle();
    expect(find.text("Logo de l'école"), findsOneWidget);
    expect(find.text('Messages automatiques (WhatsApp)'), findsOneWidget);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(repo.autoCalls, [true]);
    expect(session.refreshes, 1);
    for (final role in ['accountant', 'secretary']) {
      await t.pumpWidget(harness(const ProfilePage(), me: meWith(role), repo: repo));
      await t.pumpAndSettle();
      expect(find.text("Logo de l'école"), findsNothing, reason: role);
      expect(find.text('Messages automatiques (WhatsApp)'), findsNothing, reason: role);
      expect(find.text('Messages aux familles'), findsOneWidget, reason: role);
    }
    await t.pumpWidget(harness(const ProfilePage(), me: meWith('teacher'), repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Messages aux familles'), findsNothing);
  });

  testWidgets('the message log shows each status and filters who must be phoned', (t) async {
    phone(t);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const MessagesPage(), me: meWith('secretary'), repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Envoyé : 1'), findsOneWidget);
    expect(find.text("Pas d'accord WhatsApp"), findsWidgets);
    expect(find.text('À appeler'), findsWidgets);
    expect(find.text('KOUASSI'), findsOneWidget);
    await t.tap(find.widgetWithText(FilterChip, 'À appeler'));
    await t.pumpAndSettle();
    expect(repo.lastMessagesFilter, 'failed,skipped');
    expect(find.text('KOUASSI'), findsNothing);
    expect(find.text('BAMBA'), findsOneWidget);
  });

  testWidgets('no overflow at 320 px, text x2: roll call, report sheet, logo sheet, messages', (t) async {
    phone(t, h: 2400, w: 320);
    final problems = <String>[];
    final repo = FakeRepo()..logoBytes = _png;
    for (final page in <Widget>[
      CourseRollPage(slot: started, date: DateTime(2026, 10, 5)),
      const MessagesPage(),
      Scaffold(body: ReportSheet(enrollmentId: 10, childName: 'Fanta TRAORE', today: DateTime(2026, 10, 5))),
      const Scaffold(body: LogoSheet()),
      const ChildPage(enrollmentId: 10, name: 'Fanta TRAORE'),
    ]) {
      await t.pumpWidget(harness(page, me: meWith('director'), repo: repo, textScale: 2.0));
      await t.pumpAndSettle();
      final e = t.takeException();
      if (e != null) problems.add('${page.runtimeType}: ${e.toString().split('\n').first}');
    }
    expect(problems, isEmpty);
  });
}

class _RefusingRoll extends FakeRepo {
  @override
  Future<({int recorded, int notified})> saveCourseRoll(int slotId, DateTime date, List<({int enrollmentId, String kind, bool justified})> notPresent) async => throw AppError('only_today', status: 400);
}
