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
}
