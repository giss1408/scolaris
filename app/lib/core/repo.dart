import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'errors.dart';
import 'money.dart';
import 'models.dart';
import 'session.dart';

/// A random key sent with each payment: if the app retries after a timeout, the server records ONE payment.
String newIdempotencyKey() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

class NewStudent {
  NewStudent({required this.lastName, required this.firstNames, required this.sex, required this.classroomId, this.birthDate, this.birthPlace, this.matricule, this.assigned = false, this.options = const [], this.parentName, this.parentPhone, this.relation = 'pere', this.optin = false, this.familyId});
  final String lastName, firstNames, sex, relation;
  final int classroomId;
  final DateTime? birthDate;
  final String? birthPlace, matricule, parentName, parentPhone;
  final bool assigned, optin;
  final List<String> options;
  final int? familyId;

  Map<String, Object?> toJson() => {
        'last_name': lastName.trim(),
        'first_names': firstNames.trim(),
        'sex': sex,
        if (birthDate != null) 'birth_date': isoDate(birthDate!),
        if ((birthPlace ?? '').trim().isNotEmpty) 'birth_place': birthPlace!.trim(),
        if ((matricule ?? '').trim().isNotEmpty) 'matricule_mena': matricule!.trim(),
        'assigned': assigned,
        if (familyId != null) 'family_id': familyId,
        'contacts': [
          if ((parentPhone ?? '').trim().isNotEmpty)
            {'name': (parentName ?? '').trim(), 'relation': relation, 'phone': AuthService.digits(parentPhone!), 'financial_responsible': true, 'whatsapp_optin': optin},
        ],
        'enrollment': {'classroom_id': classroomId, 'options': options},
      };
}

/// Everything the screens ask of the server. An interface so screens can be tested with a fake.
abstract class SchoolRepo {
  Future<Dashboard> dashboard(int yearId);
  Future<List<StudentRow>> students(int yearId, {String? query, int offset = 0});
  Future<StudentDetail> student(int id, int enrollmentId, String classroom);
  Future<EnrollmentAccount> account(int enrollmentId);
  Future<StudentRow> createStudent(NewStudent s);
  Future<PaymentRow> pay(int enrollmentId, {required int amount, required String method, String? reference, required String idempotencyKey});
  Future<void> cancelPayment(int paymentId, String reason);
  Future<void> grantDiscount(int enrollmentId, {required String kind, required int amount, required String reason});
  Future<Receipt> receipt(int paymentId);
  Future<List<ArrearsFamily>> arrears(int yearId);
  Future<List<Classroom>> classrooms(int yearId);
  Future<Classroom> addClassroom(int yearId, String level, String name);
  Future<List<FeeLine>> fees(int yearId, String level);
  Future<void> saveFees(int yearId, String level, List<FeeLine> lines);
  Future<List<StaffRow>> staff();
  Future<void> addStaff(String name, String phone, String role);
  Future<void> removeStaff(int id);
  Future<List<Subject>> subjects();
  Future<Subject> addSubject(String name);
  Future<Map<int, int>> coefficients(int yearId, String level);
  Future<void> saveCoefficients(int yearId, String level, Map<int, int> coefs);
  Future<List<Evaluation>> evaluations(int classroomId, {int? period});
  Future<Evaluation> addEvaluation({required int classroomId, required int subjectId, required int period, required String kind, String? title, required int maxScore});
  Future<({Evaluation evaluation, List<GradeRow> rows})> grades(int evaluationId);
  Future<void> saveGrades(int evaluationId, List<GradeRow> rows);
  Future<void> setLocked(int evaluationId, bool locked);
  Future<ClassResults> results(int classroomId, int period);
  Future<ReportCard> reportCard(int enrollmentId, int period);
  Future<void> saveRemark(int enrollmentId, {required int period, String? conduct, String? appreciation, String? sanction, String? decision});
  Future<void> recordAbsences(int classroomId, DateTime day, List<({int enrollmentId, String kind, bool justified})> entries);
  Future<List<({int enrollmentId, String kind, bool justified})>> absencesOfDay(int classroomId, DateTime day);
  Future<List<ReminderItem>> reminders();
  Future<void> markReminderSent(int id);
  Future<void> skipReminder(int id);
  Future<void> recordPromise(int familyId, {required int amount, required DateTime promisedFor});
  // parent space
  Future<List<ChildRow>> children();
  Future<List<PaymentRow>> childPayments(int enrollmentId);
  Future<ReportCard> childReportCard(int enrollmentId, int period);
  Future<List<AbsenceRow>> childAbsences(int enrollmentId);
  // exports (CSV text, semicolon separated: opens in Excel)
  Future<String> headcountCsv(int yearId);
  Future<String> examCandidatesCsv(int yearId);
}

final repoProvider = Provider<SchoolRepo>((ref) => HttpRepo(ref.watch(apiDioProvider)));

class HttpRepo implements SchoolRepo {
  HttpRepo(this._d);
  final Dio _d;

  Future<T> _get<T>(String path, {Map<String, Object?>? q}) async {
    try {
      return (await _d.get<T>(path, queryParameters: q)).data as T;
    } catch (e) {
      throw mapError(e);
    }
  }

  Future<T> _send<T>(String method, String path, {Object? body}) async {
    try {
      return (await _d.request<T>(path, data: body, options: Options(method: method))).data as T;
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<Dashboard> dashboard(int yearId) async => Dashboard.fromJson(await _get<Map<String, dynamic>>('/v1/dashboard', q: {'year_id': yearId}));

  @override
  Future<List<StudentRow>> students(int yearId, {String? query, int offset = 0}) async {
    final r = await _get<List<dynamic>>('/v1/students', q: {'year_id': yearId, if ((query ?? '').trim().isNotEmpty) 'q': query!.trim(), 'offset': offset, 'limit': 50});
    return [for (final j in r) StudentRow.fromJson(j as Map<String, dynamic>)];
  }

  @override
  Future<StudentDetail> student(int id, int enrollmentId, String classroom) async =>
      StudentDetail.fromJson(await _get<Map<String, dynamic>>('/v1/students/$id'), enrollmentId: enrollmentId, classroom: classroom);

  @override
  Future<EnrollmentAccount> account(int enrollmentId) async => EnrollmentAccount.fromJson(await _get<Map<String, dynamic>>('/v1/enrollments/$enrollmentId/account'));

  @override
  Future<StudentRow> createStudent(NewStudent s) async {
    final j = await _send<Map<String, dynamic>>('POST', '/v1/students', body: s.toJson());
    return StudentRow.fromJson({...j, 'classroom': '', 'enrollment_id': j['enrollment_id']});
  }

  @override
  Future<PaymentRow> pay(int enrollmentId, {required int amount, required String method, String? reference, required String idempotencyKey}) async {
    final j = await _send<Map<String, dynamic>>('POST', '/v1/enrollments/$enrollmentId/payments',
        body: {'amount': amount, 'method': method, if ((reference ?? '').trim().isNotEmpty) 'reference': reference!.trim(), 'idempotency_key': idempotencyKey});
    return PaymentRow.fromJson(j['payment'] as Map<String, dynamic>);
  }

  @override
  Future<void> cancelPayment(int paymentId, String reason) => _send<Object?>('POST', '/v1/payments/$paymentId/cancel', body: {'reason': reason.trim()});

  @override
  Future<void> grantDiscount(int enrollmentId, {required String kind, required int amount, required String reason}) =>
      _send<Object?>('POST', '/v1/enrollments/$enrollmentId/discounts', body: {'kind': kind, 'amount': amount, 'reason': reason.trim()});

  @override
  Future<Receipt> receipt(int paymentId) async => Receipt.fromJson(await _get<Map<String, dynamic>>('/v1/payments/$paymentId/receipt'));

  @override
  Future<List<ArrearsFamily>> arrears(int yearId) async {
    final r = await _get<List<dynamic>>('/v1/arrears', q: {'year_id': yearId});
    return [for (final j in r) ArrearsFamily.fromJson(j as Map<String, dynamic>)];
  }

  @override
  Future<List<Classroom>> classrooms(int yearId) async {
    final r = await _get<List<dynamic>>('/v1/classrooms', q: {'year_id': yearId});
    return [for (final j in r) Classroom.fromJson(j as Map<String, dynamic>)];
  }

  @override
  Future<Classroom> addClassroom(int yearId, String level, String name) async =>
      Classroom.fromJson(await _send<Map<String, dynamic>>('POST', '/v1/classrooms', body: {'year_id': yearId, 'level': level, 'name': name.trim()}));

  @override
  Future<List<FeeLine>> fees(int yearId, String level) async {
    final r = await _get<List<dynamic>>('/v1/fees', q: {'year_id': yearId, 'level': level});
    return [for (final j in r) FeeLine.fromJson(j as Map<String, dynamic>)];
  }

  @override
  Future<void> saveFees(int yearId, String level, List<FeeLine> lines) => _send<Object?>('PUT', '/v1/fees', body: {
        'year_id': yearId,
        'level': level,
        'lines': [for (final l in lines) {'kind': l.kind, 'label': l.label.trim(), 'amount': l.amount, 'due_date': isoDate(l.dueDate), 'optional': l.optional, 'applies_to': l.appliesTo}],
      });

  @override
  Future<List<StaffRow>> staff() async {
    final r = await _get<List<dynamic>>('/v1/staff');
    return [for (final j in r) StaffRow.fromJson(j as Map<String, dynamic>)];
  }

  @override
  Future<void> addStaff(String name, String phone, String role) => _send<Object?>('POST', '/v1/staff', body: {'display_name': name.trim(), 'phone': AuthService.digits(phone), 'role': role});

  @override
  Future<void> removeStaff(int id) => _send<Object?>('DELETE', '/v1/staff/$id');

  @override
  Future<List<Subject>> subjects() async => [for (final j in await _get<List<dynamic>>('/v1/subjects')) Subject.fromJson(j as Map<String, dynamic>)];

  @override
  Future<Subject> addSubject(String name) async => Subject.fromJson(await _send<Map<String, dynamic>>('POST', '/v1/subjects', body: {'name': name.trim()}));

  @override
  Future<Map<int, int>> coefficients(int yearId, String level) async {
    final r = await _get<List<dynamic>>('/v1/coefficients', q: {'year_id': yearId, 'level': level});
    return {for (final j in r) (j as Map<String, dynamic>)['subject_id'] as int: j['coef'] as int};
  }

  @override
  Future<void> saveCoefficients(int yearId, String level, Map<int, int> coefs) => _send<Object?>('PUT', '/v1/coefficients', body: {
        'year_id': yearId,
        'level': level,
        'lines': [for (final e in coefs.entries) {'subject_id': e.key, 'coef': e.value}],
      });

  @override
  Future<List<Evaluation>> evaluations(int classroomId, {int? period}) async {
    final r = await _get<List<dynamic>>('/v1/evaluations', q: {'classroom_id': classroomId, if (period != null) 'period': period});
    return [for (final j in r) Evaluation.fromJson(j as Map<String, dynamic>)];
  }

  @override
  Future<Evaluation> addEvaluation({required int classroomId, required int subjectId, required int period, required String kind, String? title, required int maxScore}) async =>
      Evaluation.fromJson(await _send<Map<String, dynamic>>('POST', '/v1/evaluations', body: {
        'classroom_id': classroomId, 'subject_id': subjectId, 'period': period, 'kind': kind, if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(), 'max_score': maxScore,
      }));

  @override
  Future<({Evaluation evaluation, List<GradeRow> rows})> grades(int evaluationId) async {
    final j = await _get<Map<String, dynamic>>('/v1/evaluations/$evaluationId/grades');
    return (
      evaluation: Evaluation.fromJson(j['evaluation'] as Map<String, dynamic>),
      rows: [for (final r in j['rows'] as List) GradeRow(enrollmentId: r['enrollment_id'] as int, name: r['name'] as String, value: r['value'] as String?, absent: r['absent'] == true)],
    );
  }

  @override
  Future<void> saveGrades(int evaluationId, List<GradeRow> rows) => _send<Object?>('PUT', '/v1/evaluations/$evaluationId/grades', body: {
        'grades': [for (final r in rows) {'enrollment_id': r.enrollmentId, 'absent': r.absent, if (!r.absent && r.value != null) 'value': r.value}],
      });

  @override
  Future<void> setLocked(int evaluationId, bool locked) => _send<Object?>('POST', '/v1/evaluations/$evaluationId/${locked ? 'lock' : 'unlock'}');

  @override
  Future<ClassResults> results(int classroomId, int period) async => ClassResults.fromJson(await _get<Map<String, dynamic>>('/v1/classrooms/$classroomId/results', q: {'period': period}));

  @override
  Future<ReportCard> reportCard(int enrollmentId, int period) async => ReportCard.fromJson(await _get<Map<String, dynamic>>('/v1/enrollments/$enrollmentId/report-card', q: {'period': period}));

  @override
  Future<void> saveRemark(int enrollmentId, {required int period, String? conduct, String? appreciation, String? sanction, String? decision}) =>
      _send<Object?>('PUT', '/v1/enrollments/$enrollmentId/remarks', body: {
        'period': period,
        if (conduct != null) 'conduct': conduct,
        if (appreciation != null) 'appreciation': appreciation,
        if (sanction != null) 'sanction': sanction,
        if (decision != null) 'decision': decision,
      });

  @override
  Future<void> recordAbsences(int classroomId, DateTime day, List<({int enrollmentId, String kind, bool justified})> entries) => _send<Object?>('POST', '/v1/absences', body: {
        'day': isoDate(day), 'classroom_id': classroomId, 'replace': true,
        'entries': [for (final e in entries) {'enrollment_id': e.enrollmentId, 'kind': e.kind, 'justified': e.justified}],
      });

  @override
  Future<List<({int enrollmentId, String kind, bool justified})>> absencesOfDay(int classroomId, DateTime day) async {
    final r = await _get<List<dynamic>>('/v1/classrooms/$classroomId/absences', q: {'day': isoDate(day)});
    return [for (final j in r) (enrollmentId: (j as Map<String, dynamic>)['enrollment_id'] as int, kind: j['kind'] as String, justified: j['justified'] == true)];
  }

  @override
  Future<List<ReminderItem>> reminders() async {
    final j = await _get<Map<String, dynamic>>('/v1/reminders');
    return [for (final r in j['items'] as List) ReminderItem.fromJson(r as Map<String, dynamic>)];
  }

  @override
  Future<void> markReminderSent(int id) => _send<Object?>('POST', '/v1/reminders/$id/sent');

  @override
  Future<void> skipReminder(int id) => _send<Object?>('POST', '/v1/reminders/$id/skip');

  @override
  Future<void> recordPromise(int familyId, {required int amount, required DateTime promisedFor}) =>
      _send<Object?>('POST', '/v1/families/$familyId/promises', body: {'amount': amount, 'promised_for': isoDate(promisedFor)});

  @override
  Future<List<ChildRow>> children() async => [for (final j in await _get<List<dynamic>>('/v1/parent/children')) ChildRow.fromJson(j as Map<String, dynamic>)];

  @override
  Future<List<PaymentRow>> childPayments(int enrollmentId) async => [
        for (final j in await _get<List<dynamic>>('/v1/parent/children/$enrollmentId/payments')) PaymentRow.fromJson({...(j as Map<String, dynamic>), 'cancelled': false}),
      ];

  @override
  Future<ReportCard> childReportCard(int enrollmentId, int period) async => ReportCard.fromJson(await _get<Map<String, dynamic>>('/v1/parent/children/$enrollmentId/report-card', q: {'period': period}));

  @override
  Future<List<AbsenceRow>> childAbsences(int enrollmentId) async => [
        for (final j in await _get<List<dynamic>>('/v1/parent/children/$enrollmentId/absences'))
          AbsenceRow(day: DateTime.parse((j as Map<String, dynamic>)['day'] as String), kind: j['kind'] as String, justified: j['justified'] == true, reason: j['reason'] as String?),
      ];

  @override
  Future<String> headcountCsv(int yearId) => _get<String>('/v1/exports/headcount', q: {'year_id': yearId, 'format': 'csv'});

  @override
  Future<String> examCandidatesCsv(int yearId) => _get<String>('/v1/exports/exam-candidates', q: {'year_id': yearId, 'format': 'csv'});
}
