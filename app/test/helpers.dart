import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:scolaris/core/errors.dart';
import 'package:scolaris/core/models.dart';
import 'package:scolaris/core/repo.dart';
import 'package:scolaris/core/session.dart';
import 'package:scolaris/core/theme.dart';

Me meWith(String role, {int id = 1, String? whatsappPhone, int toSend = 0}) => Me(
      whatsappPhone: whatsappPhone, messagesToSend: toSend,
      staffId: id, name: 'Awa Koné', role: role, schoolName: 'Groupe Scolaire Les Palmiers', city: 'Abidjan', yearId: 1, yearLabel: '2026-2027',
      levels: const {'college': ['6e', '5e']}, feeKinds: const ['scolarite', 'cantine'], methods: const ['especes', 'wave'],
    );

class FakeSession extends SessionController {
  FakeSession(this.me, {this.signInError, this.admin = false});
  final Me? me;
  final AppError? signInError;

  /// Signed in as a member of the Scolaris team.
  final bool admin;
  int signOuts = 0;
  final calls = <String>[];

  @override
  SessionState build() => me == null && !admin ? const SessionState(SessionStatus.signedOut) : SessionState(SessionStatus.signedIn, me: me, admin: admin);

  @override
  Future<void> signIn(String phone, String password, {bool parent = false, bool admin = false, String? totp}) async {
    calls.add('signIn parent=$parent admin=$admin totp=${totp ?? ''}');
    if (signInError != null) throw signInError!;
  }

  @override
  Future<void> registerParent(String phone, String password, String name) async => calls.add('register $name');

  @override
  Future<void> activate(String phone, String code, String password, {bool parent = false}) async => calls.add('activate parent=$parent');

  int refreshes = 0;
  final stepUps = <({String password, String? totp})>[];
  @override
  Future<void> refreshProfile() async => refreshes++;
  @override
  Future<void> stepUp(String password, {String? totp}) async => stepUps.add((password: password, totp: totp));

  @override
  Future<void> signOut() async {
    signOuts++;
    state = const SessionState(SessionStatus.signedOut);
  }
}

class FakeRepo implements SchoolRepo {
  FakeRepo({this.arrearsData = const [], this.failDashboard = false});
  final List<ArrearsFamily> arrearsData;
  final bool failDashboard;
  final paid = <({int enrollmentId, int amount, String method, String key})>[];

  @override
  Future<Dashboard> dashboard(int yearId) async {
    if (failDashboard) throw AppError('offline');
    return const Dashboard(today: 150000, month: 1250000, year: 8000000, expected: 20000000, remaining: 12000000, overdue: 3500000, students: 240, recoveryPct: 40);
  }

  @override
  Future<List<ArrearsFamily>> arrears(int yearId) async => arrearsData;

  @override
  Future<List<StudentRow>> students(int yearId, {String? query, int offset = 0}) async => [
        const StudentRow(id: 1, enrollmentId: 10, name: 'KOUASSI Aya', classroom: '6e 1', internalNumber: 'ELV-2026-000001', matricule: '20123456A'),
        const StudentRow(id: 2, enrollmentId: 11, name: 'YAO Koffi', classroom: '5e 2', internalNumber: 'ELV-2026-000002', assigned: true),
      ];

  @override
  Future<EnrollmentAccount> account(int enrollmentId) async => EnrollmentAccount(
        enrollmentId: enrollmentId, studentName: 'KOUASSI Aya', classroom: '6e 1',
        account: AccountView(totalDue: 235000, credited: 30000, remaining: 205000, overdue: 100000, creditBalance: 0, lines: [
          AccountLine(label: 'Inscription', kind: 'inscription', amount: 30000, covered: 30000, remaining: 0, dueDate: DateTime(2026, 9, 14), lateDays: 0),
          AccountLine(label: '1re tranche', kind: 'scolarite', amount: 100000, covered: 0, remaining: 100000, dueDate: DateTime(2026, 10, 14), lateDays: 12),
        ]),
        payments: [PaymentRow(id: 5, kind: 'payment', amount: 30000, method: 'especes', receipt: 'REC-2026-000001', paidAt: DateTime(2026, 9, 14))],
        discounts: const [],
      );

  @override
  Future<StudentDetail> student(int id, int enrollmentId, String classroom) async => StudentDetail(
        id: id, name: 'KOUASSI Aya', internalNumber: 'ELV-2026-000001', sex: 'F', assigned: false, matricule: '20123456A', birthDate: DateTime(2014, 3, 2), birthPlace: 'Abidjan',
        contacts: const [Contact(id: 5, name: 'Kouassi Paul', relation: 'pere', phone: '+2250701020304', masked: '07 •• •• 03 04', channel: 'whatsapp', optin: true, financial: true)],
        siblings: const [(id: 3, name: 'KOUASSI Koffi')], enrollmentId: enrollmentId, classroom: classroom,
      );

  @override
  Future<PaymentRow> pay(int enrollmentId, {required int amount, required String method, String? reference, required String idempotencyKey}) async {
    paid.add((enrollmentId: enrollmentId, amount: amount, method: method, key: idempotencyKey));
    return PaymentRow(id: 99, kind: 'payment', amount: amount, method: method, receipt: 'REC-2026-000002', paidAt: DateTime(2026, 11, 23));
  }

  @override
  Future<Receipt> receipt(int paymentId) async => Receipt(
        school: 'Groupe Scolaire Les Palmiers', city: 'Abidjan', year: '2026-2027', kind: 'payment', number: 'REC-2026-000002', date: DateTime(2026, 11, 23),
        studentName: 'KOUASSI Aya', internalNumber: 'ELV-2026-000001', classroom: '6e 1', amount: 50000, method: 'wave', reference: 'WV1', remainingAfter: 155000, cashier: 'Caissier',
      );

  @override
  Future<List<Classroom>> classrooms(int yearId) async => rooms;
  @override
  Future<List<StaffRow>> staff() async => staffRows;
  List<StaffRow> staffRows = const [StaffRow(id: 1, name: 'Awa Koné', role: 'director', active: true), StaffRow(id: 2, name: 'Marie Caisse', role: 'accountant', active: true), StaffRow(id: 3, name: 'Prof Math', role: 'teacher', active: true), StaffRow(id: 4, name: 'Prof Francais', role: 'teacher', active: true)];

  @override
  Future<StudentRow> createStudent(NewStudent s) => throw UnimplementedError();
  @override
  Future<void> cancelPayment(int paymentId, String reason) async {}
  @override
  Future<void> grantDiscount(int enrollmentId, {required String kind, required int amount, required String reason}) async {}
  @override
  Future<Classroom> addClassroom(int yearId, String level, String name) => throw UnimplementedError();
  @override
  Future<List<FeeLine>> fees(int yearId, String level) async => const [];
  @override
  Future<void> saveFees(int yearId, String level, List<FeeLine> lines) async {}
  @override
  Future<void> addStaff(String name, String phone, String role) async {}
  @override
  Future<void> removeStaff(int id) async {}

  List<ChildRow> kids = const [
    ChildRow(enrollmentId: 10, name: 'Fanta TRAORE', school: 'Ecole A', classroom: '6e 1', year: '2026-2027', remaining: 205000, overdue: 100000, totalDue: 235000),
    ChildRow(enrollmentId: 20, name: 'Moussa TRAORE', school: 'Ecole B', classroom: 'CM2 A', year: '2026-2027', remaining: 0, overdue: 0, totalDue: 85000),
  ];
  @override
  Future<List<ChildRow>> children() async => kids;
  @override
  Future<List<PaymentRow>> childPayments(int enrollmentId) async => [PaymentRow(id: 5, kind: 'payment', amount: 30000, method: 'wave', receipt: 'REC-2026-000001', paidAt: DateTime(2026, 9, 14))];
  @override
  Future<ReportCard> childReportCard(int enrollmentId, int period) => reportCard(enrollmentId, period);
  @override
  Future<List<AbsenceRow>> childAbsences(int enrollmentId) async => [AbsenceRow(day: DateTime(2026, 10, 3), kind: 'absence', justified: false)];
  @override
  Future<String> headcountCsv(int yearId) async => 'Niveau;Garçons\n6e;3';
  @override
  Future<String> examCandidatesCsv(int yearId) async => 'Examen;Nom\nCEPE;TRAORE';

  // timetable
  /// The same two periods every day Monday-Saturday, so a screen that opens on "today" has something to show whatever day the tests run.
  ClassTimetable timetable = ClassTimetable(editable: true, slots: [
    for (var d = 1; d <= 6; d++) ...[
      Slot(id: d * 10 + 1, classroomId: 1, classroom: '6e 1', weekday: d, start: '08:00', end: '09:00', subjectId: 1, subject: 'Mathématiques', teacherId: 3, teacher: 'Prof Math', room: 'A1'),
      Slot(id: d * 10 + 2, classroomId: 1, classroom: '6e 1', weekday: d, start: '10:00', end: '11:00', subjectId: 2, subject: 'Français', teacherId: 4, teacher: 'Prof Francais'),
    ],
  ], teachers: const [TimetableTeacher(id: 3, name: 'Prof Math', subjectIds: [1]), TimetableTeacher(id: 4, name: 'Prof Francais', subjectIds: [2])]);
  final addedSlots = <({int weekday, String start, String end, int subjectId, int? teacherId, String? room})>[];
  final deletedSlots = <int>[];
  AppError? addSlotError;
  @override
  Future<ClassTimetable> classTimetable(int classroomId) async => timetable;
  @override
  Future<void> addSlot(int classroomId, {required int weekday, required String start, required String end, required int subjectId, int? teacherId, String? room}) async {
    if (addSlotError != null) throw addSlotError!;
    addedSlots.add((weekday: weekday, start: start, end: end, subjectId: subjectId, teacherId: teacherId, room: room));
  }
  @override
  Future<void> deleteSlot(int slotId) async => deletedSlots.add(slotId);
  List<Cancellation> cancellations = const [];
  final cancelledCalls = <({int slotId, DateTime date, String reason, String? note})>[];
  final restoredCalls = <({int slotId, DateTime date})>[];
  AppError? cancelError;
  List<CancelledSession> upcoming = const [];
  @override
  Future<Week> myWeek() async => Week(slots: timetable.slots, cancellations: cancellations);
  @override
  Future<Week> childTimetable(int enrollmentId) async => Week(slots: timetable.slots, cancellations: cancellations);
  @override
  Future<void> cancelSession(int slotId, DateTime date, {required String reason, String? note, int? substituteStaffId}) async {
    if (cancelError != null) throw cancelError!;
    cancelledCalls.add((slotId: slotId, date: date, reason: reason, note: note));
    cancelSubstitutes.add(substituteStaffId);
  }
  final cancelSubstitutes = <int?>[];
  @override
  Future<void> restoreSession(int slotId, DateTime date) async => restoredCalls.add((slotId: slotId, date: date));
  @override
  Future<List<CancelledSession>> upcomingCancellations() async => upcoming;

  // ---- roll call of a course, parent reports, substitutes, logo, messages, subscription, platform team
  List<RollRow> rollRows = const [
    RollRow(enrollmentId: 10, name: 'KOUASSI Aya'),
    RollRow(enrollmentId: 11, name: 'YAO Koffi', reportedReason: 'maladie', reportedNote: 'Palu'),
    RollRow(enrollmentId: 12, name: 'ZADI Mariam', absentAllDay: true),
  ];
  final savedRolls = <({int slotId, DateTime date, List<({int enrollmentId, String kind, bool justified})> entries})>[];
  int rollNotified = 2;
  @override
  Future<List<RollRow>> courseRoll(int slotId, DateTime date) async => rollRows;
  @override
  Future<({int recorded, int notified})> saveCourseRoll(int slotId, DateTime date, List<({int enrollmentId, String kind, bool justified})> notPresent) async {
    savedRolls.add((slotId: slotId, date: date, entries: notPresent));
    return (recorded: notPresent.length, notified: rollNotified);
  }
  @override
  Future<List<AbsenceReport>> classAbsenceReports(int classroomId, DateTime day) async => const [];
  List<TeacherRef> teacherRefs = const [TeacherRef(id: 3, name: 'Prof Math'), TeacherRef(id: 4, name: 'Prof Francais')];
  final substitutes = <({int slotId, DateTime date, int? staffId})>[];
  @override
  Future<List<TeacherRef>> teachers() async => teacherRefs;
  @override
  Future<void> setSubstitute(int slotId, DateTime date, int? staffId) async => substitutes.add((slotId: slotId, date: date, staffId: staffId));
  final reported = <({int enrollmentId, DateTime day, String reason, String? note})>[];
  final withdrawn = <DateTime>[];
  List<AbsenceReport> myReports = const [];
  @override
  Future<void> reportAbsence(int enrollmentId, DateTime day, {required String reason, String? note}) async => reported.add((enrollmentId: enrollmentId, day: day, reason: reason, note: note));
  @override
  Future<List<AbsenceReport>> childAbsenceReports(int enrollmentId) async => myReports;
  @override
  Future<void> withdrawAbsenceReport(int enrollmentId, DateTime day) async => withdrawn.add(day);
  Uint8List? logoBytes;
  final uploadedLogos = <String>[];
  bool logoDeleted = false;
  AppError? uploadError;
  @override
  Future<Uint8List?> schoolLogo() async => logoBytes;
  @override
  Future<Uint8List?> parentSchoolLogo(int schoolId) async => logoBytes;
  @override
  Future<void> uploadLogo(Uint8List bytes, String contentType) async {
    if (uploadError != null) throw uploadError!;
    uploadedLogos.add('$contentType:${bytes.length}');
  }
  @override
  Future<void> deleteLogo() async => logoDeleted = true;
  final autoCalls = <bool>[];
  @override
  Future<void> setAutoWhatsapp(bool on) async => autoCalls.add(on);
  MessageLog messageLog = MessageLog(summary: const {'sent': 1, 'skipped': 1}, items: [
    MessageRow(id: 1, family: 'KOUASSI', kind: 'absence', status: 'sent', text: 'Fanta a été noté(e) absent(e)…', createdAt: DateTime(2026, 11, 23), needsCall: false),
    MessageRow(id: 2, family: 'BAMBA', kind: 'cancellation', status: 'skipped', text: 'Le cours de Maths est annulé.', createdAt: DateTime(2026, 11, 23), needsCall: true, detail: 'no_whatsapp_optin'),
  ]);
  String? lastMessagesFilter;
  @override
  Future<MessageLog> messages({String? status}) async {
    lastMessagesFilter = status;
    return status == null ? messageLog : MessageLog(summary: messageLog.summary, items: messageLog.items.where((m) => m.needsCall).toList());
  }
  BillingInfo billingInfo = BillingInfo(
      payTo: const PayTo(methods: [PayMethod(operator: 'wave', number: '+2250701020304', holder: 'Scolaris SARL'), PayMethod(operator: 'orange_money', number: '+2250505050505', holder: 'Scolaris SARL')], reference: 'SCO-12', note: 'Envoyez la capture au 07…', amount: 100000),
      status: 'active', standing: Standing(monthlyAmount: 50000, billingDay: 5, remaining: 100000, overdueMonths: 2, oldestLateDays: 49, late: true, nextDue: DateTime(2026, 12, 5)), notices: [
    Notice(id: 7, kind: 'reminder', title: 'Rappel : mensualité Scolaris en retard', text: 'La mensualité est en retard.', createdAt: DateTime(2026, 11, 20)),
  ]);
  final seenNotices = <int>[];
  @override
  Future<BillingInfo> billing() async => billingInfo;
  @override
  Future<void> markNoticeSeen(int id) async => seenNotices.add(id);
  List<AdminSchool> adminList = [
    AdminSchool(id: 1, name: 'Ecole Bloquée', status: 'blocked', reminders: 2, finalNotices: 1, standing: Standing(monthlyAmount: 50000, billingDay: 5, remaining: 150000, overdueMonths: 3, oldestLateDays: 80, late: true, nextDue: DateTime(2026, 12, 5))),
    AdminSchool(id: 2, name: 'Ecole En Retard', status: 'active', reminders: 1, finalNotices: 0, standing: Standing(monthlyAmount: 30000, billingDay: 5, remaining: 60000, overdueMonths: 2, oldestLateDays: 40, late: true, nextDue: DateTime(2026, 12, 5))),
    AdminSchool(id: 3, name: "Ecole A l'heure", status: 'active', reminders: 0, finalNotices: 0, standing: Standing(monthlyAmount: 30000, billingDay: 5, remaining: 0, overdueMonths: 0, oldestLateDays: 0, late: false, nextDue: DateTime(2026, 12, 5))),
  ];
  late AdminSchoolDetail adminDetail = AdminSchoolDetail(
    school: adminList[1], standing: adminList[1].standing, reminders: 1, finalNotices: 0,
    notices: [Notice(id: 5, kind: 'reminder', title: 'Rappel', text: 'En retard', createdAt: DateTime(2026, 11, 20), seenBy: 1, audience: 2)],
    payments: [AdminPayment(amount: 30000, method: 'wave', paidOn: DateTime(2026, 10, 6), reference: 'WV1')],
  );
  final adminCalls = <String>[];
  AppError? adminError;
  @override
  Future<List<AdminSchool>> adminSchools() async => adminList;
  @override
  Future<AdminSchoolDetail> adminSchool(int id) async => adminDetail;
  @override
  Future<void> adminSetSubscription(int schoolId, {int? monthlyAmount, required int billingDay, required DateTime startedOn, int graceDays = 5}) async => adminCalls.add('subscription ${monthlyAmount ?? 'default'}/$billingDay');
  PaymentInfo paymentInfo = const PaymentInfo(methods: [PayMethod(operator: 'wave', number: '+2250701020304', holder: 'Scolaris SARL')], defaultMonthlyAmount: 30000, note: 'Indiquez la référence');
  final savedPaymentInfo = <({List<String> methods, int? price, String? note})>[];
  @override
  Future<PaymentInfo> adminPaymentInfo() async => paymentInfo;
  @override
  Future<void> adminSetPaymentInfo(List<PayMethod> methods, {int? defaultMonthlyAmount, String? note}) async {
    if (stepUpOnce) {
      stepUpOnce = false;
      throw AppError('step_up_required', status: 403);
    }
    savedPaymentInfo.add((methods: [for (final m in methods) '${m.operator}:${m.number}'], price: defaultMonthlyAmount, note: note));
  }
  bool stepUpOnce = false; // the first sensitive call is refused until the password is re-typed
  @override
  Future<void> adminRecordPayment(int schoolId, {required int amount, required String method, String? reference, DateTime? paidOn}) async {
    if (stepUpOnce) {
      stepUpOnce = false;
      throw AppError('step_up_required', status: 403);
    }
    adminCalls.add('payment $amount $method');
  }
  @override
  Future<void> adminSendNotice(int schoolId, String kind, {DateTime? blockOn, String? title, String? text}) async {
    if (adminError != null) throw adminError!;
    adminCalls.add('notice $kind${blockOn == null ? '' : ' ${blockOn.toIso8601String().substring(0, 10)}'}');
  }
  @override
  Future<void> adminBlock(int schoolId, String reason) async {
    if (adminError != null) throw adminError!;
    adminCalls.add('block $reason');
  }
  @override
  Future<void> adminUnblock(int schoolId) async {
    if (stepUpOnce) {
      stepUpOnce = false;
      throw AppError('step_up_required', status: 403);
    }
    adminCalls.add('unblock');
  }

  // ---- manual WhatsApp: the app composes, the secretary forwards from the school's own number
  ToSendList toSend = ToSendList(schoolPhone: '+2250705060708', canSendNow: true, items: [
    ToSendItem(id: 1, family: 'KOUASSI', kind: 'absence', text: "Bonjour Kouassi Paul, message de l'école Ecole A : Fanta a été noté(e) absent(e). Merci de votre confiance.", createdAt: DateTime(2026, 11, 23), waLink: 'https://wa.me/2250701020304?text=x'),
    ToSendItem(id: 2, family: 'BAMBA', kind: 'cancellation', text: 'Le cours de Maths est annulé.', createdAt: DateTime(2026, 11, 23), waLink: 'https://wa.me/2250505050505?text=y'),
  ]);
  final forwarded = <int>[];
  final setAside = <int>[];
  final whatsappNumbers = <String?>[];
  final optins = <({int id, bool on})>[];
  @override
  Future<ToSendList> messagesToSend() async => toSend;
  @override
  Future<void> markMessageSent(int id) async => forwarded.add(id);
  @override
  Future<void> skipMessage(int id) async => setAside.add(id);
  @override
  Future<void> setWhatsappPhone(String? phone) async => whatsappNumbers.add(phone);
  @override
  Future<void> setContactOptin(int contactId, bool optin) async => optins.add((id: contactId, on: optin));

  final reminderItems = <ReminderItem>[];
  final sentReminders = <int>[];
  final promises = <({int familyId, int amount})>[];
  final savedGrades = <GradeRow>[];

  @override
  Future<List<Subject>> subjects({int? classroomId}) async =>
      classroomId != null && mySubjectIds != null ? [for (final s in _all) if (mySubjectIds!.contains(s.id)) s] : _all;
  static const _all = [Subject(id: 1, name: 'Mathématiques'), Subject(id: 2, name: 'Français')];

  /// What a teacher may give in the class (null = everything).
  Set<int>? mySubjectIds;
  List<Classroom> rooms = const [Classroom(id: 1, name: '6e 1', level: '6e')];
  ClassTeachers classTeachersData = const ClassTeachers(headTeacherId: null, assignments: [(staffId: 3, name: 'Prof Math', subjectId: 1)]);
  ({int? head, List<({int staffId, int? subjectId})> list})? savedTeachers;
  @override
  Future<ClassTeachers> classTeachers(int classroomId) async => classTeachersData;
  @override
  Future<void> saveClassTeachers(int classroomId, {int? headTeacherId, required List<({int staffId, int? subjectId})> assignments}) async => savedTeachers = (head: headTeacherId, list: assignments);
  @override
  Future<Subject> addSubject(String name) async => Subject(id: 9, name: name);
  @override
  Future<Map<int, int>> coefficients(int yearId, String level) async => {1: 3, 2: 2};
  @override
  Future<void> saveCoefficients(int yearId, String level, Map<int, int> coefs) async {}
  @override
  Future<List<Evaluation>> evaluations(int classroomId, {int? period}) async =>
      [Evaluation(id: 7, subjectId: 1, period: 1, kind: 'devoir', heldOn: DateTime(2026, 10, 12), maxScore: 20, locked: false)];
  @override
  Future<Evaluation> addEvaluation({required int classroomId, required int subjectId, required int period, required String kind, String? title, required int maxScore}) async =>
      Evaluation(id: 8, subjectId: subjectId, period: period, kind: kind, heldOn: DateTime(2026, 10, 12), maxScore: maxScore, locked: false);
  @override
  Future<({Evaluation evaluation, List<GradeRow> rows})> grades(int evaluationId) async => (
        evaluation: Evaluation(id: evaluationId, subjectId: 1, period: 1, kind: 'devoir', heldOn: DateTime(2026, 10, 12), maxScore: 20, locked: false),
        rows: const [GradeRow(enrollmentId: 10, name: 'KOUASSI Aya', value: '15.00'), GradeRow(enrollmentId: 11, name: 'YAO Koffi')],
      );
  @override
  Future<void> saveGrades(int evaluationId, List<GradeRow> rows) async => savedGrades.addAll(rows);
  @override
  Future<void> setLocked(int evaluationId, bool locked) async {}
  @override
  Future<ClassResults> results(int classroomId, int period) async => const ClassResults(
        subjects: [(id: 1, name: 'Mathématiques', coef: 3)],
        classAverage: '12.50',
        rows: [
          ResultRow(enrollmentId: 11, name: 'YAO Koffi', subjects: {'1': '9.00'}, average: '9.00', position: 2, passes: false),
          ResultRow(enrollmentId: 10, name: 'KOUASSI Aya', subjects: {'1': '16.00'}, average: '16.00', position: 1, honour: 'felicitations', passes: true),
          ResultRow(enrollmentId: 12, name: 'ZADI Mariam', subjects: {'1': null}),
        ],
      );
  @override
  Future<ReportCard> reportCard(int enrollmentId, int period) async => const ReportCard(
        school: 'Groupe Scolaire Les Palmiers', classroom: '6e 1', period: 1, studentName: 'KOUASSI Aya', average: '16.00', rank: '1er sur 3', honour: 'felicitations', passes: true,
        classAverage: '12.50', conduct: '17.50', appreciation: 'Élève sérieuse', absUnjustified: 1, absJustified: 2, late: 0,
        lines: [(subject: 'Mathématiques', coef: 3, average: '16.00', classAverage: '12.50'), (subject: 'Français', coef: 2, average: null, classAverage: null)],
      );
  @override
  Future<void> saveRemark(int enrollmentId, {required int period, String? conduct, String? appreciation, String? sanction, String? decision}) async {}
  @override
  Future<void> recordAbsences(int classroomId, DateTime day, List<({int enrollmentId, String kind, bool justified})> entries) async {}
  @override
  Future<List<({int enrollmentId, String kind, bool justified})>> absencesOfDay(int classroomId, DateTime day) async => const [];
  @override
  Future<List<ReminderItem>> reminders() async => reminderItems;
  @override
  Future<void> markReminderSent(int id) async => sentReminders.add(id);
  @override
  Future<void> skipReminder(int id) async {}
  @override
  Future<void> recordPromise(int familyId, {required int amount, required DateTime promisedFor}) async => promises.add((familyId: familyId, amount: amount));
}

ArrearsFamily family() => const ArrearsFamily(
      name: 'KOUASSI', total: 270000, oldestLateDays: 12, contactName: 'Kouassi Paul', contactPhone: '+2250701020304',
      children: [
        ArrearsChild(enrollmentId: 10, studentId: 1, name: 'KOUASSI Aya', classroom: '6e 1', overdue: 135000, lateLines: [(label: '1re tranche', remaining: 100000, lateDays: 12)]),
        ArrearsChild(enrollmentId: 11, studentId: 2, name: 'KOUASSI Koffi', classroom: '5e 2', overdue: 135000, lateLines: [(label: '1re tranche', remaining: 100000, lateDays: 12)]),
      ],
    );

Widget harness(Widget child, {required Me? me, FakeRepo? repo, FakeSession? session, double textScale = 1.0}) => ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => session ?? FakeSession(me)),
        repoProvider.overrideWithValue(repo ?? FakeRepo(arrearsData: [family()])),
      ],
      key: UniqueKey(),
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(
          theme: buildTheme(),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: child,
        ),
      ),
    );

/// Overrides for tests that build their own ProviderScope.
Override sessionProvider2(FakeSession s) => sessionProvider.overrideWith(() => s);
Override repoOverride(SchoolRepo r) => repoProvider.overrideWithValue(r);
Widget harnessChild(Widget child) => Theme(data: buildTheme(), child: child);
