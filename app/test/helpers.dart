import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:scolaris/core/errors.dart';
import 'package:scolaris/core/models.dart';
import 'package:scolaris/core/repo.dart';
import 'package:scolaris/core/session.dart';
import 'package:scolaris/core/theme.dart';

Me meWith(String role) => Me(
      staffId: 1, name: 'Awa Koné', role: role, schoolName: 'Groupe Scolaire Les Palmiers', city: 'Abidjan', yearId: 1, yearLabel: '2026-2027',
      levels: const {'college': ['6e', '5e']}, feeKinds: const ['scolarite', 'cantine'], methods: const ['especes', 'wave'],
    );

class FakeSession extends SessionController {
  FakeSession(this.me, {this.signInError});
  final Me? me;
  final AppError? signInError;
  int signOuts = 0;

  @override
  SessionState build() => me == null ? const SessionState(SessionStatus.signedOut) : SessionState(SessionStatus.signedIn, me: me);

  @override
  Future<void> signIn(String phone, String password) async {
    if (signInError != null) throw signInError!;
  }

  @override
  Future<void> activate(String phone, String code, String password) async {}

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
        contacts: const [Contact(name: 'Kouassi Paul', relation: 'pere', phone: '+2250701020304', masked: '07 •• •• 03 04', channel: 'whatsapp', optin: true, financial: true)],
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
  Future<List<Classroom>> classrooms(int yearId) async => const [Classroom(id: 1, name: '6e 1', level: '6e')];
  @override
  Future<List<StaffRow>> staff() async => const [StaffRow(id: 1, name: 'Awa Koné', role: 'director', active: true), StaffRow(id: 2, name: 'Marie Caisse', role: 'accountant', active: true)];

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
