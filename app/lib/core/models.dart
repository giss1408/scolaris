import 'package:flutter/foundation.dart';

DateTime _d(Object? v) => DateTime.parse(v as String);

@immutable
class Me {
  const Me({required this.staffId, required this.name, required this.role, required this.schoolName, this.city, this.yearId, this.yearLabel, this.levels = const {}, this.feeKinds = const [], this.methods = const [], this.hasLogo = false, this.logoVersion, this.autoWhatsapp = false, this.banner, this.whatsappPhone, this.messagesToSend = 0});
  final int staffId;
  final String name, role, schoolName;
  final String? city, yearLabel;
  final int? yearId;
  final Map<String, List<String>> levels;
  final List<String> feeKinds, methods;
  final bool hasLogo, autoWhatsapp;

  /// The school's own WhatsApp number: messages are forwarded from it, parents' replies arrive on it.
  final String? whatsappPhone;

  /// Messages the app composed that a person still has to forward.
  final int messagesToSend;

  /// Changes when the logo changes: the app fetches the image again only then.
  final String? logoVersion;

  /// What the Scolaris team told the school about its subscription (director and secretary only).
  final BillingBanner? banner;
  bool get blocked => banner?.level == 'blocked';

  bool get isDirector => role == 'director';
  bool get canCollect => role == 'director' || role == 'accountant';
  bool get canEnrol => role == 'director' || role == 'secretary';
  bool get canGrade => role == 'director' || role == 'secretary' || role == 'teacher';

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
      hasLogo: j['school']['has_logo'] == true,
      logoVersion: j['school']['logo_version'] as String?,
      autoWhatsapp: j['school']['auto_whatsapp'] == true,
      whatsappPhone: j['school']['whatsapp_phone'] as String?,
      messagesToSend: (j['school']['messages_to_send'] as int?) ?? 0,
      banner: j['billing_banner'] == null ? null : BillingBanner.fromJson(j['billing_banner'] as Map<String, dynamic>),
    );
  }
}

/// The line at the top of the app: `late` (reminder), `final` (final notice with a date), `blocked`, or `info` (unread notices).
@immutable
class BillingBanner {
  const BillingBanner({required this.level, required this.title, required this.text, this.blockOn, this.unseen = 0});
  final String level, title, text;
  final DateTime? blockOn;
  final int unseen;
  factory BillingBanner.fromJson(Map<String, dynamic> j) => BillingBanner(
        level: j['level'] as String, title: (j['title'] as String?) ?? '', text: (j['text'] as String?) ?? '', unseen: (j['unseen'] as int?) ?? 0,
        blockOn: j['block_on'] == null ? null : DateTime.parse(j['block_on'] as String),
      );
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
  const Contact({this.id = 0, required this.name, required this.relation, required this.phone, required this.masked, required this.channel, required this.optin, required this.financial});
  final int id;
  final String name, relation, phone, masked, channel;
  final bool optin, financial;
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        id: (j['id'] as int?) ?? 0, name: j['name'] as String, relation: j['relation'] as String, phone: j['phone'] as String, masked: j['phone_masked'] as String,
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
  const Classroom({required this.id, required this.name, required this.level, this.isHead = false});
  final int id;
  final String name, level;

  /// The caller is this class's head teacher (professeur principal): she writes conduct and appreciation.
  final bool isHead;
  factory Classroom.fromJson(Map<String, dynamic> j) => Classroom(id: j['id'] as int, name: j['name'] as String, level: j['level'] as String, isHead: j['is_head'] == true);
}

@immutable
class ClassTeachers {
  const ClassTeachers({this.headTeacherId, this.assignments = const []});
  final int? headTeacherId;

  /// subjectId null = all the subjects she gives in this class.
  final List<({int staffId, String name, int? subjectId})> assignments;
  factory ClassTeachers.fromJson(Map<String, dynamic> j) => ClassTeachers(
        headTeacherId: j['head_teacher_id'] as int?,
        assignments: [for (final a in j['assignments'] as List) (staffId: a['staff_id'] as int, name: a['name'] as String, subjectId: a['subject_id'] as int?)],
      );
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

@immutable
class Subject {
  const Subject({required this.id, required this.name});
  final int id;
  final String name;
  factory Subject.fromJson(Map<String, dynamic> j) => Subject(id: j['id'] as int, name: j['name'] as String);
}

@immutable
class Evaluation {
  const Evaluation({required this.id, required this.subjectId, required this.period, required this.kind, required this.heldOn, required this.maxScore, required this.locked, this.title});
  final int id, subjectId, period, maxScore;
  final String kind;
  final String? title;
  final DateTime heldOn;
  final bool locked;
  factory Evaluation.fromJson(Map<String, dynamic> j) => Evaluation(
        id: j['id'] as int, subjectId: j['subject_id'] as int, period: j['period'] as int, kind: j['kind'] as String, title: j['title'] as String?,
        heldOn: _d(j['held_on']), maxScore: j['max_score'] as int, locked: j['locked'] == true,
      );
}

@immutable
class GradeRow {
  const GradeRow({required this.enrollmentId, required this.name, this.value, this.absent = false});
  final int enrollmentId;
  final String name;
  final String? value;
  final bool absent;
}

@immutable
class ResultRow {
  const ResultRow({required this.enrollmentId, required this.name, required this.subjects, this.average, this.position, this.tie = false, this.honour, this.passes});
  final int enrollmentId;
  final String name;
  final Map<String, String?> subjects;
  final String? average, honour;
  final int? position;
  final bool tie;
  final bool? passes;
  String get rankLabel => position == null ? '—' : '$position${position == 1 ? 'er' : 'e'}${tie ? ' ex' : ''}';
}

@immutable
class ClassResults {
  const ClassResults({required this.subjects, required this.rows, this.classAverage});
  final List<({int id, String name, int coef})> subjects;
  final List<ResultRow> rows;
  final String? classAverage;
  factory ClassResults.fromJson(Map<String, dynamic> j) => ClassResults(
        subjects: [for (final s in j['subjects'] as List) (id: s['id'] as int, name: s['name'] as String, coef: s['coef'] as int)],
        classAverage: j['class_average'] as String?,
        rows: [
          for (final r in j['rows'] as List)
            ResultRow(
              enrollmentId: r['enrollment_id'] as int, name: r['name'] as String, average: r['average'] as String?, honour: r['honour'] as String?, passes: r['passes'] as bool?,
              subjects: {for (final e in (r['subjects'] as Map).entries) e.key as String: e.value as String?},
              position: (r['rank'] as Map?)?['position'] as int?, tie: (r['rank'] as Map?)?['tie'] == true,
            ),
        ],
      );
}

@immutable
class ReportCard {
  const ReportCard({required this.school, required this.classroom, required this.period, required this.studentName, required this.lines, this.average, this.rank, this.honour, this.passes, this.classAverage, this.conduct, this.appreciation, this.sanction, this.decision, required this.absUnjustified, required this.absJustified, required this.late});
  final String school, classroom, studentName;
  final int period;
  final List<({String subject, int coef, String? average, String? classAverage})> lines;
  final String? average, rank, honour, classAverage, conduct, appreciation, sanction, decision;
  final bool? passes;
  final int absUnjustified, absJustified, late;
  factory ReportCard.fromJson(Map<String, dynamic> j) {
    final r = j['rank'] as Map?;
    final ab = j['absences'] as Map;
    return ReportCard(
      school: j['school']['name'] as String, classroom: j['classroom']['name'] as String, period: j['period'] as int, studentName: j['student']['name'] as String,
      lines: [for (final l in j['lines'] as List) (subject: l['subject'] as String, coef: l['coef'] as int, average: l['average'] as String?, classAverage: l['class_average'] as String?)],
      average: j['average'] as String?, honour: j['honour'] as String?, passes: j['passes'] as bool?, classAverage: j['class_average'] as String?,
      rank: r == null ? null : '${r['position']}${r['position'] == 1 ? 'er' : 'e'}${r['tie'] == true ? ' ex' : ''} sur ${r['of']}',
      conduct: j['conduct'] as String?, appreciation: j['appreciation'] as String?, sanction: j['sanction'] as String?, decision: j['decision'] as String?,
      absUnjustified: ab['days_unjustified'] as int, absJustified: ab['days_justified'] as int, late: ab['late'] as int,
    );
  }
}

@immutable
class ReminderItem {
  const ReminderItem({required this.id, required this.familyId, required this.familyName, required this.step, required this.channel, required this.amount, required this.text, required this.canSendNow, this.contactName, this.phone, this.waLink});
  final int id, familyId, amount;
  final String familyName, step, channel, text;
  final bool canSendNow;
  final String? contactName, phone, waLink;
  factory ReminderItem.fromJson(Map<String, dynamic> j) => ReminderItem(
        id: j['id'] as int, familyId: j['family_id'] as int, familyName: j['family_name'] as String, step: j['step'] as String, channel: j['channel'] as String, amount: j['amount'] as int,
        text: j['text'] as String, canSendNow: j['can_send_now'] == true, contactName: j['contact_name'] as String?, phone: j['phone'] as String?, waLink: j['wa_link'] as String?,
      );
}

@immutable
class ChildRow {
  const ChildRow({required this.enrollmentId, required this.name, required this.school, required this.classroom, required this.year, required this.remaining, required this.overdue, required this.totalDue, this.schoolId = 0, this.hasLogo = false, this.logoVersion, this.blocked = false});
  final int enrollmentId, remaining, overdue, totalDue, schoolId;
  final String name, school, classroom, year;
  final bool hasLogo, blocked;
  final String? logoVersion;
  factory ChildRow.fromJson(Map<String, dynamic> j) => ChildRow(
        enrollmentId: j['enrollment_id'] as int, name: j['name'] as String, school: j['school'] as String, classroom: j['classroom'] as String, year: j['year'] as String,
        remaining: j['balance']['remaining'] as int, overdue: j['balance']['overdue'] as int, totalDue: j['balance']['total_due'] as int,
        schoolId: (j['school_id'] as int?) ?? 0, hasLogo: j['has_logo'] == true, logoVersion: j['logo_version'] as String?, blocked: j['blocked'] == true,
      );
}

@immutable
class AbsenceRow {
  const AbsenceRow({required this.day, required this.kind, required this.justified, this.reason, this.course});
  final DateTime day;
  final String kind;
  final bool justified;
  final String? reason;

  /// Set when the absence was noted during a course (the subject and its hours).
  final ({String subject, String start, String end})? course;
}

@immutable
class Slot {
  const Slot({required this.id, required this.classroomId, required this.classroom, required this.weekday, required this.start, required this.end, required this.subjectId, required this.subject, this.teacherId, this.teacher, this.room});
  final int id, classroomId, weekday, subjectId;
  final String classroom, start, end, subject;
  final int? teacherId;
  final String? teacher, room;

  /// 1 = Monday ... 6 = Saturday.
  int get startMinutes => _minutes(start);
  int get endMinutes => _minutes(end);
  static int _minutes(String hhmm) => int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));

  factory Slot.fromJson(Map<String, dynamic> j) => Slot(
        id: j['id'] as int, classroomId: j['classroom_id'] as int, classroom: j['classroom'] as String, weekday: j['weekday'] as int, start: j['start'] as String, end: j['end'] as String,
        subjectId: j['subject_id'] as int, subject: j['subject'] as String, teacherId: j['teacher_id'] as int?, teacher: j['teacher'] as String?, room: j['room'] as String?,
      );
}

@immutable
class TimetableTeacher {
  const TimetableTeacher({required this.id, required this.name, this.subjectIds});
  final int id;
  final String name;

  /// null = all the subjects she gives in this class.
  final List<int>? subjectIds;
  bool gives(int subjectId) => subjectIds == null || subjectIds!.contains(subjectId);
}

/// One session of a period that will not take place. `reason` is only sent to the administration and to the teacher concerned.
@immutable
class Cancellation {
  const Cancellation({required this.slotId, required this.date, this.reason, this.note, this.substitute, this.substituteId});
  final int slotId;
  final DateTime date;
  final String? reason, note, substitute;
  final int? substituteId;
  bool matches(int slot, DateTime day) => slotId == slot && date.year == day.year && date.month == day.month && date.day == day.day;
  factory Cancellation.fromJson(Map<String, dynamic> j) => Cancellation(slotId: j['slot_id'] as int, date: DateTime.parse(j['date'] as String), reason: j['reason'] as String?, note: j['note'] as String?, substitute: j['substitute'] as String?, substituteId: j['substitute_id'] as int?);
}

/// Periods of a week and the sessions cancelled around today.
@immutable
class Week {
  const Week({required this.slots, this.cancellations = const [], this.substitutions = const []});
  final List<Slot> slots;
  final List<Cancellation> cancellations;

  /// Sessions this teacher covers for a colleague, each with its date.
  final List<({Slot slot, DateTime date})> substitutions;
  factory Week.fromJson(Map<String, dynamic> j) => Week(
        substitutions: [for (final s in (j['substitutions'] as List?) ?? const []) (slot: Slot.fromJson(s as Map<String, dynamic>), date: DateTime.parse(s['date'] as String))],
        slots: [for (final s in j['slots'] as List) Slot.fromJson(s as Map<String, dynamic>)],
        cancellations: [for (final c in (j['cancellations'] as List?) ?? const []) Cancellation.fromJson(c as Map<String, dynamic>)],
      );
}

/// A cancelled session as the administration sees it, with the message to send to the families.
@immutable
class CancelledSession {
  const CancelledSession({required this.slotId, required this.date, required this.start, required this.end, required this.classroom, required this.subject, required this.reason, required this.message, this.teacher, this.note, this.substitute});
  final int slotId;
  final DateTime date;
  final String start, end, classroom, subject, reason, message;
  final String? teacher, note, substitute;
  factory CancelledSession.fromJson(Map<String, dynamic> j) => CancelledSession(
        slotId: j['slot_id'] as int, date: DateTime.parse(j['date'] as String), start: j['start'] as String, end: j['end'] as String, classroom: j['classroom'] as String,
        subject: j['subject'] as String, teacher: j['teacher'] as String?, reason: j['reason'] as String, note: j['note'] as String?, message: j['message'] as String, substitute: j['substitute'] as String?,
      );
}

@immutable
class ClassTimetable {
  const ClassTimetable({required this.slots, required this.editable, this.teachers = const [], this.cancellations = const []});
  final List<Slot> slots;
  final bool editable;
  final List<TimetableTeacher> teachers;
  final List<Cancellation> cancellations;
  factory ClassTimetable.fromJson(Map<String, dynamic> j) => ClassTimetable(
        slots: [for (final s in j['slots'] as List) Slot.fromJson(s as Map<String, dynamic>)],
        cancellations: [for (final c in (j['cancellations'] as List?) ?? const []) Cancellation.fromJson(c as Map<String, dynamic>)],
        editable: j['editable'] == true,
        teachers: [for (final t in (j['teachers'] as List?) ?? const []) TimetableTeacher(id: t['id'] as int, name: t['name'] as String, subjectIds: (t['subject_ids'] as List?)?.cast<int>())],
      );
}

/// One pupil in the roll call of a COURSE: present, absent or late; with what the parents reported for the day.
@immutable
class RollRow {
  const RollRow({required this.enrollmentId, required this.name, this.status = 'present', this.justified = false, this.absentAllDay = false, this.reportedReason, this.reportedNote});
  final int enrollmentId;
  final String name, status;
  final bool justified, absentAllDay;
  final String? reportedReason, reportedNote;
  factory RollRow.fromJson(Map<String, dynamic> j) => RollRow(
        enrollmentId: j['enrollment_id'] as int, name: j['name'] as String, status: j['status'] as String, justified: j['justified'] == true, absentAllDay: j['absent_all_day'] == true,
        reportedReason: (j['reported'] as Map?)?['reason'] as String?, reportedNote: (j['reported'] as Map?)?['note'] as String?,
      );
}

/// An absence a parent reported for a day.
@immutable
class AbsenceReport {
  const AbsenceReport({required this.day, required this.reason, this.note, this.enrollmentId, this.name, this.classroom});
  final DateTime day;
  final String reason;
  final String? note, name, classroom;
  final int? enrollmentId;
  factory AbsenceReport.fromJson(Map<String, dynamic> j) => AbsenceReport(
        day: DateTime.parse((j['day'] as String?) ?? DateTime.now().toIso8601String().substring(0, 10)), reason: j['reason'] as String, note: j['note'] as String?,
        enrollmentId: j['enrollment_id'] as int?, name: j['name'] as String?, classroom: j['classroom'] as String?,
      );
}

@immutable
class TeacherRef {
  const TeacherRef({required this.id, required this.name});
  final int id;
  final String name;
}

/// A message to a family and where it stands. `needsCall` = it could not go by WhatsApp: the staff phone instead.
@immutable
class MessageRow {
  const MessageRow({required this.id, required this.family, required this.kind, required this.status, required this.text, required this.createdAt, required this.needsCall, this.detail});
  final int id;
  final String? family, detail;
  final String kind, status, text;
  final DateTime createdAt;
  final bool needsCall;
  factory MessageRow.fromJson(Map<String, dynamic> j) => MessageRow(
        id: j['id'] as int, family: j['family'] as String?, kind: j['kind'] as String, status: j['status'] as String, text: j['text'] as String, createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        needsCall: j['needs_call'] == true, detail: j['detail'] as String?,
      );
}

@immutable
class MessageLog {
  const MessageLog({required this.summary, required this.items});
  final Map<String, int> summary;
  final List<MessageRow> items;
  factory MessageLog.fromJson(Map<String, dynamic> j) => MessageLog(
        summary: {for (final e in (j['summary'] as Map).entries) e.key as String: e.value as int},
        items: [for (final i in j['items'] as List) MessageRow.fromJson(i as Map<String, dynamic>)],
      );
}

/// What a school owes the Scolaris team: its monthly subscription.
@immutable
class Standing {
  const Standing({required this.monthlyAmount, required this.billingDay, required this.remaining, required this.overdueMonths, required this.oldestLateDays, required this.late, required this.nextDue, this.billed = 0, this.paid = 0, this.graceDays = 5});
  final int monthlyAmount, billingDay, remaining, overdueMonths, oldestLateDays, billed, paid, graceDays;
  final bool late;
  final DateTime nextDue;
  factory Standing.fromJson(Map<String, dynamic> j) => Standing(
        monthlyAmount: j['monthly_amount'] as int, billingDay: (j['billing_day'] as int?) ?? 5, remaining: j['remaining'] as int, overdueMonths: j['overdue_months'] as int, oldestLateDays: j['oldest_late_days'] as int,
        late: j['late'] == true, nextDue: DateTime.parse(j['next_due'] as String), billed: (j['billed'] as int?) ?? 0, paid: (j['paid'] as int?) ?? 0, graceDays: (j['grace_days'] as int?) ?? 5,
      );
}

@immutable
class Notice {
  const Notice({required this.id, required this.kind, required this.title, required this.text, required this.createdAt, this.blockOn, this.seen = false, this.seenBy = 0, this.audience = 0});
  final int id, seenBy, audience;
  final String kind, title, text;
  final DateTime createdAt;
  final DateTime? blockOn;
  final bool seen;
  factory Notice.fromJson(Map<String, dynamic> j) => Notice(
        id: j['id'] as int, kind: j['kind'] as String, title: j['title'] as String, text: j['text'] as String, createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        blockOn: j['block_on'] == null ? null : DateTime.parse(j['block_on'] as String), seen: j['seen'] == true, seenBy: (j['seen_by'] as int?) ?? 0, audience: (j['audience'] as int?) ?? 0,
      );
}

@immutable
class BillingInfo {
  const BillingInfo({required this.status, this.standing, this.notices = const [], this.payTo});
  final String status;
  final Standing? standing;
  final List<Notice> notices;

  /// Where and how to pay the subscription (the numbers the Scolaris team entered).
  final PayTo? payTo;
  factory BillingInfo.fromJson(Map<String, dynamic> j) => BillingInfo(
        payTo: j['pay_to'] == null ? null : PayTo.fromJson(j['pay_to'] as Map<String, dynamic>),
        status: j['status'] as String, standing: j['standing'] == null ? null : Standing.fromJson(j['standing'] as Map<String, dynamic>),
        notices: [for (final n in j['notices'] as List) Notice.fromJson(n as Map<String, dynamic>)],
      );
}

/// A school as the Scolaris team sees it.
@immutable
class AdminSchool {
  const AdminSchool({required this.id, required this.name, required this.status, required this.reminders, required this.finalNotices, this.city, this.standing});
  final int id, reminders, finalNotices;
  final String name, status;
  final String? city;
  final Standing? standing;
  bool get blocked => status == 'blocked';
  factory AdminSchool.fromJson(Map<String, dynamic> j) => AdminSchool(
        id: j['id'] as int, name: j['name'] as String, status: j['status'] as String, city: j['city'] as String?, reminders: j['reminders'] as int, finalNotices: j['final_notices'] as int,
        standing: j['subscription'] == null ? null : Standing.fromJson(j['subscription'] as Map<String, dynamic>),
      );
}

@immutable
class AdminPayment {
  const AdminPayment({required this.amount, required this.method, required this.paidOn, this.reference});
  final int amount;
  final String method;
  final DateTime paidOn;
  final String? reference;
}

@immutable
class AdminSchoolDetail {
  const AdminSchoolDetail({required this.school, required this.notices, required this.payments, required this.reminders, required this.finalNotices, this.standing, this.blockedReason, this.lastFinalBlockOn});
  final AdminSchool school;
  final Standing? standing;
  final List<Notice> notices;
  final List<AdminPayment> payments;
  final int reminders, finalNotices;
  final String? blockedReason;
  final DateTime? lastFinalBlockOn;
  factory AdminSchoolDetail.fromJson(Map<String, dynamic> j) {
    final s = j['school'] as Map<String, dynamic>;
    final st = j['subscription'] == null ? null : Standing.fromJson(j['subscription'] as Map<String, dynamic>);
    return AdminSchoolDetail(
      school: AdminSchool(id: s['id'] as int, name: s['name'] as String, status: s['status'] as String, city: s['city'] as String?, reminders: j['reminders'] as int, finalNotices: j['final_notices'] as int, standing: st),
      standing: st, reminders: j['reminders'] as int, finalNotices: j['final_notices'] as int, blockedReason: s['blocked_reason'] as String?,
      lastFinalBlockOn: j['last_final_block_on'] == null ? null : DateTime.parse(j['last_final_block_on'] as String),
      notices: [for (final n in j['notices'] as List) Notice.fromJson(n as Map<String, dynamic>)],
      payments: [for (final p in j['payments'] as List) AdminPayment(amount: p['amount'] as int, method: p['method'] as String, paidOn: DateTime.parse(p['paid_on'] as String), reference: p['reference'] as String?)],
    );
  }
}

/// A message the app composed: the secretary taps it, WhatsApp opens on the school's phone with the text ready, she sends it and marks it done.
@immutable
class ToSendItem {
  const ToSendItem({required this.id, required this.family, required this.kind, required this.text, required this.createdAt, this.waLink});
  final int id;
  final String? family, waLink;
  final String kind, text;
  final DateTime createdAt;
  factory ToSendItem.fromJson(Map<String, dynamic> j) => ToSendItem(
        id: j['id'] as int, family: j['family'] as String?, kind: j['kind'] as String, text: j['text'] as String, createdAt: DateTime.parse(j['created_at'] as String).toLocal(), waLink: j['wa_link'] as String?,
      );
}

@immutable
class ToSendList {
  const ToSendList({required this.items, required this.canSendNow, this.schoolPhone});
  final List<ToSendItem> items;
  final bool canSendNow;
  final String? schoolPhone;
  factory ToSendList.fromJson(Map<String, dynamic> j) => ToSendList(
        schoolPhone: j['school_phone'] as String?, canSendNow: j['can_send_now'] == true, items: [for (final i in j['items'] as List) ToSendItem.fromJson(i as Map<String, dynamic>)],
      );
}

/// A Mobile Money number of the Scolaris team. `holder` is the name the operator shows when money is sent, to check it goes to the right person.
@immutable
class PayMethod {
  const PayMethod({required this.operator, required this.number, required this.holder});
  final String operator, number, holder;
  factory PayMethod.fromJson(Map<String, dynamic> j) => PayMethod(operator: j['operator'] as String, number: j['number'] as String, holder: j['holder'] as String);
}

/// What a school sees to pay: the numbers, the reference to quote, the amount to pay now.
@immutable
class PayTo {
  const PayTo({required this.methods, required this.reference, this.note, this.amount});
  final List<PayMethod> methods;
  final String reference;
  final String? note;
  final int? amount;
  factory PayTo.fromJson(Map<String, dynamic> j) => PayTo(
        methods: [for (final m in j['methods'] as List) PayMethod.fromJson(m as Map<String, dynamic>)], reference: j['reference'] as String, note: j['note'] as String?, amount: j['amount'] as int?,
      );
}

/// The team's settings: the numbers schools pay to, the usual monthly price, a note.
@immutable
class PaymentInfo {
  const PaymentInfo({required this.methods, this.defaultMonthlyAmount, this.note});
  final List<PayMethod> methods;
  final int? defaultMonthlyAmount;
  final String? note;
  factory PaymentInfo.fromJson(Map<String, dynamic> j) => PaymentInfo(
        methods: [for (final m in j['methods'] as List) PayMethod.fromJson(m as Map<String, dynamic>)], defaultMonthlyAmount: j['default_monthly_amount'] as int?, note: j['note'] as String?,
      );
}
