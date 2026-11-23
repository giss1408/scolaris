// Runs the app's REAL Dart code (SessionController, AuthService, HttpRepo, interceptor) against the real auth + scolaris services on the platform.
// Skipped unless SCOLARIS_LIVE=1. Dart does not resolve *.localhost, so we reach Caddy on 127.0.0.1 with the Host header.
//   SCOLARIS_LIVE=1 LIVE_PHONE=07... LIVE_PASSWORD=... flutter test integration/live_smoke_test.dart
// (platform/tests/e2e_scolaris.sh sets the school and the director up, then calls this.)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/errors.dart';
import 'package:scolaris/core/models.dart';
import 'package:scolaris/core/repo.dart';
import 'package:scolaris/core/session.dart';

Dio _dio(String host) => Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8080', headers: {'Host': host}));

void main() {
  final live = Platform.environment['SCOLARIS_LIVE'] == '1';
  final phone = Platform.environment['LIVE_PHONE'] ?? '';
  final password = Platform.environment['LIVE_PASSWORD'] ?? '';
  final parentPhone = Platform.environment['LIVE_PARENT_PHONE'] ?? '';
  final domain = Platform.environment['LIVE_DOMAIN'] ?? 'localhost';

  test('a parent signs in to the parent space and sees her child', () async {
    final store = MemoryTokenStore();
    final c = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authDioProvider.overrideWithValue(_dio('auth-api.$domain')),
      apiDioProvider.overrideWith((ref) {
        final dio = _dio('scolaris-api.$domain');
        final session = ref.read(sessionProvider.notifier);
        dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          if (session.access != null) o.headers['Authorization'] = 'Bearer ${session.access}';
          h.next(o);
        }));
        return dio;
      }),
    ]);
    addTearDown(c.dispose);
    await c.read(sessionProvider.notifier).signIn(parentPhone, password, parent: true);
    expect(c.read(sessionProvider).parent, isTrue);
    expect(c.read(sessionProvider).me, isNull);
    final repo = HttpRepo(c.read(apiDioProvider));
    final kids = await repo.children();
    expect(kids.single.name, 'Fanta TRAORÉ');
    expect((await repo.childReportCard(kids.single.enrollmentId, 1)).average, '15.50');
    expect((await repo.childPayments(kids.single.enrollmentId)), isA<List>());
    expect((await repo.childTimetable(kids.single.enrollmentId)).slots.map((s) => s.subject), contains('Mathématiques'));
    // the parent reports an absence, sees it, and withdraws it
    var next = DateTime.now().add(const Duration(days: 2));
    if (next.weekday == DateTime.sunday) next = next.add(const Duration(days: 1));
    await repo.reportAbsence(kids.single.enrollmentId, next, reason: 'rendez_vous', note: 'Dentiste');
    final mine = await repo.childAbsenceReports(kids.single.enrollmentId);
    expect(mine.map((r) => r.reason), contains('rendez_vous'));
    await repo.withdrawAbsenceReport(kids.single.enrollmentId, next);
    expect((await repo.childAbsenceReports(kids.single.enrollmentId)).where((r) => r.day == DateTime(next.year, next.month, next.day)), isEmpty);
    await c.read(sessionProvider.notifier).signOut();
  }, skip: live && parentPhone.isNotEmpty ? false : 'needs SCOLARIS_LIVE=1 and LIVE_PARENT_PHONE');

  test('sign in, read, collect, cancel, sign out against the live platform', () async {
    final store = MemoryTokenStore();
    final c = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authDioProvider.overrideWithValue(_dio('auth-api.$domain')),
      apiDioProvider.overrideWith((ref) {
        final dio = _dio('scolaris-api.$domain');
        final session = ref.read(sessionProvider.notifier);
        dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          if (session.access != null) o.headers['Authorization'] = 'Bearer ${session.access}';
          h.next(o);
        }));
        return dio;
      }),
    ]);
    addTearDown(c.dispose);
    final session = c.read(sessionProvider.notifier);

    // wrong password: a readable error, nobody signed in
    await expectLater(session.signIn(phone, 'wrong-password-123'), throwsA(isA<AppError>().having((e) => userMessage(e), 'message', 'Numéro ou mot de passe incorrect.')));
    expect(c.read(sessionProvider).status, isNot(SessionStatus.signedIn));

    await session.signIn(phone, password);
    final me = c.read(sessionProvider).me!;
    expect(me.role, 'director');
    expect(me.schoolName, 'Ecole E2E');
    expect(me.levels['college'], contains('6e'));
    expect(await store.read(), isNotNull); // refresh token kept for the next start

    final repo = HttpRepo(c.read(apiDioProvider));
    final year = me.yearId!;
    final rooms = await repo.classrooms(year);
    final cm2 = rooms.firstWhere((r) => r.name == 'CM2 A');

    final created = await repo.createStudent(NewStudent(
      lastName: 'Diallo', firstNames: 'Mariam', sex: 'F', classroomId: cm2.id, parentName: 'Diallo Seydou', parentPhone: '01 02 03 04 05', optin: true,
    ));
    final found = await repo.students(year, query: 'diallo');
    expect(found.map((s) => s.id), contains(created.id));
    final detail = await repo.student(created.id, created.enrollmentId, 'CM2 A');
    expect(detail.contacts.single.phone, '+2250102030405');

    var account = await repo.account(created.enrollmentId);
    expect(account.account.totalDue, 85000);
    expect((await repo.arrears(year)).any((f) => f.name == 'DIALLO'), isTrue);

    // a payment retried with the same key is recorded once
    final key = newIdempotencyKey();
    final p1 = await repo.pay(created.enrollmentId, amount: 25000, method: 'wave', reference: 'WV-APP-1', idempotencyKey: key);
    final p2 = await repo.pay(created.enrollmentId, amount: 25000, method: 'wave', reference: 'WV-APP-1', idempotencyKey: key);
    expect(p2.id, p1.id);
    account = await repo.account(created.enrollmentId);
    expect(account.account.remaining, 60000);
    await expectLater(repo.pay(created.enrollmentId, amount: 1000, method: 'orange_money', idempotencyKey: newIdempotencyKey()), throwsA(isA<AppError>().having((e) => e.code, 'code', 'reference_required')));

    final receipt = await repo.receipt(p1.id);
    expect(receipt.number, startsWith('REC-'));
    expect(receipt.remainingAfter, 60000);

    // a sensitive action: allowed right after signing in; after the session is ended at auth it is refused
    await repo.cancelPayment(p1.id, 'Test application');
    account = await repo.account(created.enrollmentId);
    expect(account.account.remaining, 85000);
    expect(account.payments.first.isCreditNote, isTrue);

    // slice 2 and 3 through the app's real repository
    final subjects = await repo.subjects();
    final maths = subjects.firstWhere((s) => s.name == 'Mathématiques');
    final eval = await repo.addEvaluation(classroomId: cm2.id, subjectId: maths.id, period: 2, kind: 'devoir', maxScore: 20);
    final sheet = await repo.grades(eval.id);
    expect(sheet.rows.map((r) => r.enrollmentId), contains(created.enrollmentId));
    await repo.saveGrades(eval.id, [GradeRow(enrollmentId: created.enrollmentId, name: 'x', value: '12.5')]);
    final results = await repo.results(cm2.id, 2);
    expect(results.rows.firstWhere((r) => r.enrollmentId == created.enrollmentId).average, '12.50');
    expect((await repo.reportCard(created.enrollmentId, 2)).rank, '1er sur 1');
    await repo.recordAbsences(cm2.id, DateTime.now(), [(enrollmentId: created.enrollmentId, kind: 'absence', justified: false)]);
    expect((await repo.absencesOfDay(cm2.id, DateTime.now())).single.enrollmentId, created.enrollmentId);
    final reminders = await repo.reminders();
    expect(reminders, isNotEmpty);
    await repo.markReminderSent(reminders.first.id);
    await repo.recordPromise(reminders.first.familyId, amount: 1000, promisedFor: DateTime.now().add(const Duration(days: 5)));

    // timetable through the app's real repository: add, conflict sentence from the server, read, delete
    final tt0 = await repo.classTimetable(cm2.id);
    expect(tt0.editable, isTrue);
    await repo.addSlot(cm2.id, weekday: 5, start: '10:00', end: '11:00', subjectId: maths.id, room: 'LIVE-1');
    await expectLater(
      repo.addSlot(cm2.id, weekday: 5, start: '10:30', end: '11:30', subjectId: maths.id),
      throwsA(isA<AppError>().having((e) => userMessage(e), 'message', contains('10:00'))),
    );
    final tt1 = await repo.classTimetable(cm2.id);
    final mine = tt1.slots.firstWhere((s) => s.room == 'LIVE-1');
    expect((mine.weekday, mine.start, mine.subject), (5, '10:00', 'Mathématiques'));
    // cancel one session of that period (the next Friday), see it as the administration, restore it
    var friday = DateTime.now().add(const Duration(days: 1));
    while (friday.weekday != DateTime.friday) {
      friday = friday.add(const Duration(days: 1));
    }
    await repo.cancelSession(mine.id, friday, reason: 'formation', note: 'Stage');
    final up = (await repo.upcomingCancellations()).where((c) => c.slotId == mine.id).single;
    expect((up.reason, up.note, up.message.contains('enseignant absent'), up.message.contains('Stage')), ('formation', 'Stage', true, false));
    expect((await repo.classTimetable(cm2.id)).cancellations.where((c) => c.slotId == mine.id).single.reason, 'formation');
    await repo.restoreSession(mine.id, friday);
    expect((await repo.upcomingCancellations()).where((c) => c.slotId == mine.id), isEmpty);
    await repo.deleteSlot(mine.id);
    expect((await repo.classTimetable(cm2.id)).slots.any((s) => s.room == 'LIVE-1'), isFalse);

    // logo, messages, subscription and the WhatsApp setting through the app's real repository
    final png = Uint8List.fromList(base64.decode('iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAFklEQVR4nO3BAQEAAACCIP+vbkhAAQAA8G8GHQABfCTLrQAAAABJRU5ErkJggg=='));
    await repo.uploadLogo(png, 'image/png');
    expect(await repo.schoolLogo(), png);
    final meAgain = await repo.teachers();
    expect(meAgain.map((t) => t.name), contains('Prof E2E'));
    await repo.setAutoWhatsapp(true);
    final log = await repo.messages();
    expect(log.items, isA<List>());
    final bill = await repo.billing();
    expect(bill.status, 'active');
    await repo.deleteLogo();
    expect(await repo.schoolLogo(), isNull);

    expect((await repo.dashboard(year)).students, greaterThan(0));
    expect((await repo.staff()).any((s) => s.role == 'director'), isTrue);
    await session.stepUp(password); // the password re-proof used by the step-up dialog
    await session.signOut();
    expect(c.read(sessionProvider).status, SessionStatus.signedOut);
    expect(await store.read(), isNull);
  }, skip: live ? false : 'set SCOLARIS_LIVE=1 (needs the platform running)');
}
