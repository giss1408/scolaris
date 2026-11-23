import 'package:flutter/foundation.dart';

DateTime _d(Object? v) => DateTime.parse(v as String);

@immutable
class Me {
  const Me({required this.staffId, required this.name, required this.role, required this.schoolName, this.city, this.yearId, this.yearLabel, this.levels = const {}, this.feeKinds = const [], this.methods = const []});
  final int staffId;
  final String name, role, schoolName;
  final String? city, yearLabel;
  final int? yearId;
  final Map<String, List<String>> levels;
  final List<String> feeKinds, methods;

  bool get isDirector => role == 'director';
  bool get canCollect => role == 'director' || role == 'accountant';
  bool get canEnrol => role == 'director' || role == 'secretary';

  factory Me.fromJson(Map<String, dynamic> j) {
    final cat = (j['catalog'] as Map?) ?? const {};
    final year = j['current_year'] as Map?;
    return Me(
      staffId: j['staff']['id'] as int,
      name: j['staff']['name'] as String,
      role: j['staff']['role'] as String,
      schoolName: j['school']['name'] as String,
      city: j['school']['city'] as String?,
      yearId: year?['id'] as int?,
      yearLabel: year?['label'] as String?,
      levels: {for (final e in ((cat['levels'] as Map?) ?? const {}).entries) e.key as String: List<String>.from(e.value as List)},
      feeKinds: List<String>.from((cat['fee_kinds'] as List?) ?? const []),
      methods: List<String>.from((cat['methods'] as List?) ?? const []),
    );
  }
}

@immutable
class Dashboard {
  const Dashboard({required this.today, required this.month, required this.year, required this.expected, required this.remaining, required this.overdue, required this.students, required this.recoveryPct});
  final int today, month, year, expected, remaining, overdue, students, recoveryPct;
  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
        today: j['collected_today'] as int, month: j['collected_month'] as int, year: j['collected_year'] as int, expected: j['expected_total'] as int,
        remaining: j['remaining_total'] as int, overdue: j['overdue_total'] as int, students: j['students'] as int, recoveryPct: j['recovery_rate_pct'] as int,
      );
}

@immutable
class StudentRow {
  const StudentRow({required this.id, required this.enrollmentId, required this.name, required this.classroom, required this.internalNumber, this.matricule, this.assigned = false});
  final int id, enrollmentId;
  final String name, classroom, internalNumber;
  final String? matricule;
  final bool assigned;
  factory StudentRow.fromJson(Map<String, dynamic> j) => StudentRow(
        id: j['id'] as int, enrollmentId: j['enrollment_id'] as int, name: '${j['last_name']} ${j['first_names']}', classroom: j['classroom'] as String,
        internalNumber: j['internal_number'] as String, matricule: j['matricule_mena'] as String?, assigned: j['assigned'] == true,
      );
}

@immutable
class Contact {
  const Contact({required this.name, required this.relation, required this.phone, required this.masked, required this.channel, required this.optin, required this.financial});
  final String name, relation, phone, masked, channel;
  final bool optin, financial;
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        name: j['name'] as String, relation: j['relation'] as String, phone: j['phone'] as String, masked: j['phone_masked'] as String,
        channel: j['preferred_channel'] as String, optin: j['whatsapp_optin'] == true, financial: j['financial_responsible'] == true,
      );
}

@immutable
class StudentDetail {
  const StudentDetail({required this.id, required this.name, required this.internalNumber, required this.sex, required this.assigned, this.matricule, this.birthDate, this.birthPlace, required this.contacts, required this.siblings, required this.enrollmentId, required this.classroom});
  final int id, enrollmentId;
  final String name, internalNumber, sex, classroom;
  final String? matricule, birthPlace;
  final DateTime? birthDate;
  final bool assigned;
  final List<Contact> contacts;
  final List<({int id, String name})> siblings;

  factory StudentDetail.fromJson(Map<String, dynamic> j, {required int enrollmentId, required String classroom}) => StudentDetail(
        id: j['id'] as int, name: '${j['last_name']} ${j['first_names']}', internalNumber: j['internal_number'] as String, sex: j['sex'] as String,
        assigned: j['assigned'] == true, matricule: j['matricule_mena'] as String?, birthPlace: j['birth_place'] as String?,
        birthDate: j['birth_date'] == null ? null : _d(j['birth_date']),
        contacts: [for (final c in j['contacts'] as List) Contact.fromJson(c as Map<String, dynamic>)],
        siblings: [for (final s in j['siblings'] as List) (id: s['id'] as int, name: s['name'] as String)],
        enrollmentId: enrollmentId, classroom: classroom,
      );
}

@immutable
class AccountLine {
  const AccountLine({required this.label, required this.kind, required this.amount, required this.covered, required this.remaining, required this.dueDate, required this.lateDays});
  final String label, kind;
  final int amount, covered, remaining, lateDays;
  final DateTime dueDate;
  bool get isPaid => remaining == 0;
  factory AccountLine.fromJson(Map<String, dynamic> j) => AccountLine(
        label: j['label'] as String, kind: j['kind'] as String, amount: j['amount'] as int, covered: j['covered'] as int, remaining: j['remaining'] as int,
        dueDate: _d(j['due_date']), lateDays: j['late_days'] as int,
      );
}

@immutable
class PaymentRow {
  const PaymentRow({required this.id, required this.kind, required this.amount, required this.method, required this.receipt, required this.paidAt, this.reference, this.reason, this.cancelled = false});
  final int id, amount;
  final String kind, method, receipt;
  final String? reference, reason;
  final DateTime paidAt;
  final bool cancelled;
  bool get isCreditNote => kind == 'credit_note';
  factory PaymentRow.fromJson(Map<String, dynamic> j) => PaymentRow(
        id: j['id'] as int, kind: j['kind'] as String, amount: j['amount'] as int, method: j['method'] as String, receipt: j['receipt_number'] as String,
        paidAt: _d(j['paid_at']).toLocal(), reference: j['reference'] as String?, reason: j['reason'] as String?, cancelled: j['cancelled'] == true,
      );
}

@immutable
class AccountView {
  const AccountView({required this.totalDue, required this.credited, required this.remaining, required this.overdue, required this.creditBalance, required this.lines});
  final int totalDue, credited, remaining, overdue, creditBalance;
  final List<AccountLine> lines;
  factory AccountView.fromJson(Map<String, dynamic> j) => AccountView(
        totalDue: j['total_due'] as int, credited: j['credited'] as int, remaining: j['remaining'] as int, overdue: j['overdue'] as int, creditBalance: j['credit_balance'] as int,
        lines: [for (final l in j['lines'] as List) AccountLine.fromJson(l as Map<String, dynamic>)],
      );
}

@immutable
class EnrollmentAccount {
  const EnrollmentAccount({required this.enrollmentId, required this.studentName, required this.classroom, required this.account, required this.payments, required this.discounts});
  final int enrollmentId;
  final String studentName, classroom;
  final AccountView account;
  final List<PaymentRow> payments;
  final List<({String kind, int amount, String reason})> discounts;
  factory EnrollmentAccount.fromJson(Map<String, dynamic> j) => EnrollmentAccount(
        enrollmentId: j['enrollment_id'] as int, studentName: j['student']['name'] as String, classroom: j['classroom'] as String,
        account: AccountView.fromJson(j['account'] as Map<String, dynamic>),
        payments: [for (final p in j['payments'] as List) PaymentRow.fromJson(p as Map<String, dynamic>)],
        discounts: [for (final d in j['discounts'] as List) (kind: d['kind'] as String, amount: d['amount'] as int, reason: d['reason'] as String)],
      );
}

@immutable
class Receipt {
  const Receipt({required this.school, required this.city, required this.year, required this.kind, required this.number, required this.date, required this.studentName, required this.internalNumber, required this.classroom, required this.amount, required this.method, required this.remainingAfter, required this.cashier, this.reference, this.reason});
  final String school, year, kind, number, studentName, internalNumber, classroom, method, cashier;
  final String? city, reference, reason;
  final DateTime date;
  final int amount, remainingAfter;
  bool get isCreditNote => kind == 'credit_note';
  factory Receipt.fromJson(Map<String, dynamic> j) => Receipt(
        school: j['school']['name'] as String, city: j['school']['city'] as String?, year: j['year'] as String, kind: j['kind'] as String, number: j['number'] as String,
        date: _d(j['date']).toLocal(), studentName: j['student']['name'] as String, internalNumber: j['student']['internal_number'] as String, classroom: j['student']['classroom'] as String,
        amount: j['amount'] as int, method: j['method'] as String, remainingAfter: j['remaining_after'] as int, cashier: j['cashier'] as String,
        reference: j['reference'] as String?, reason: j['reason'] as String?,
      );
}

@immutable
class ArrearsChild {
  const ArrearsChild({required this.enrollmentId, required this.studentId, required this.name, required this.classroom, required this.overdue, required this.lateLines});
  final int enrollmentId, studentId, overdue;
  final String name, classroom;
  final List<({String label, int remaining, int lateDays})> lateLines;
}

@immutable
class ArrearsFamily {
  const ArrearsFamily({required this.name, required this.total, required this.oldestLateDays, required this.children, this.contactName, this.contactPhone});
  final String name;
  final int total, oldestLateDays;
  final List<ArrearsChild> children;
  final String? contactName, contactPhone;
  factory ArrearsFamily.fromJson(Map<String, dynamic> j) {
    final c = j['contact'] as Map?;
    return ArrearsFamily(
      name: j['family_name'] as String, total: j['overdue_total'] as int, oldestLateDays: j['oldest_late_days'] as int,
      contactName: c?['name'] as String?, contactPhone: c?['phone'] as String?,
      children: [
        for (final k in j['children'] as List)
          ArrearsChild(
            enrollmentId: k['enrollment_id'] as int, studentId: k['student_id'] as int, name: k['name'] as String, classroom: k['classroom'] as String, overdue: k['overdue'] as int,
            lateLines: [for (final l in k['late_lines'] as List) (label: l['label'] as String, remaining: l['remaining'] as int, lateDays: l['late_days'] as int)],
          ),
      ],
    );
  }
}

@immutable
class Classroom {
  const Classroom({required this.id, required this.name, required this.level});
  final int id;
  final String name, level;
  factory Classroom.fromJson(Map<String, dynamic> j) => Classroom(id: j['id'] as int, name: j['name'] as String, level: j['level'] as String);
}

@immutable
class FeeLine {
  const FeeLine({required this.kind, required this.label, required this.amount, required this.dueDate, this.optional = false, this.appliesTo = 'all'});
  final String kind, label, appliesTo;
  final int amount;
  final DateTime dueDate;
  final bool optional;
  factory FeeLine.fromJson(Map<String, dynamic> j) => FeeLine(
        kind: j['kind'] as String, label: j['label'] as String, amount: j['amount'] as int, dueDate: _d(j['due_date']), optional: j['optional'] == true, appliesTo: j['applies_to'] as String,
      );
}

@immutable
class StaffRow {
  const StaffRow({required this.id, required this.name, required this.role, required this.active});
  final int id;
  final String name, role;
  final bool active;
  factory StaffRow.fromJson(Map<String, dynamic> j) => StaffRow(id: j['id'] as int, name: j['name'] as String, role: j['role'] as String, active: j['active'] == true);
}
