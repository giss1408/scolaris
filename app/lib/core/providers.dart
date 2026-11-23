import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'repo.dart';
import 'session.dart';

/// The signed-in staff member (only read below the sign-in gate).
final meProvider = Provider<Me>((ref) => ref.watch(sessionProvider).me!);

int _year(Ref ref) => ref.watch(meProvider).yearId ?? 0;

final dashboardProvider = FutureProvider.autoDispose<Dashboard>((ref) => ref.watch(repoProvider).dashboard(_year(ref)));
final arrearsProvider = FutureProvider.autoDispose<List<ArrearsFamily>>((ref) => ref.watch(repoProvider).arrears(_year(ref)));
final accountProvider = FutureProvider.autoDispose.family<EnrollmentAccount, int>((ref, enrollmentId) => ref.watch(repoProvider).account(enrollmentId));
final studentProvider = FutureProvider.autoDispose.family<StudentDetail, ({int id, int enrollmentId, String classroom})>(
    (ref, k) => ref.watch(repoProvider).student(k.id, k.enrollmentId, k.classroom));
final receiptProvider = FutureProvider.autoDispose.family<Receipt, int>((ref, id) => ref.watch(repoProvider).receipt(id));
final classroomsProvider = FutureProvider.autoDispose<List<Classroom>>((ref) => ref.watch(repoProvider).classrooms(_year(ref)));
final staffProvider = FutureProvider.autoDispose<List<StaffRow>>((ref) => ref.watch(repoProvider).staff());

final subjectsProvider = FutureProvider.autoDispose<List<Subject>>((ref) => ref.watch(repoProvider).subjects());

/// The subjects the signed-in person may give in one class (a teacher: only hers).
final classSubjectsProvider = FutureProvider.autoDispose.family<List<Subject>, int>((ref, classroomId) => ref.watch(repoProvider).subjects(classroomId: classroomId));
final classTeachersProvider = FutureProvider.autoDispose.family<ClassTeachers, int>((ref, classroomId) => ref.watch(repoProvider).classTeachers(classroomId));
final evaluationsProvider = FutureProvider.autoDispose.family<List<Evaluation>, int>((ref, classroomId) => ref.watch(repoProvider).evaluations(classroomId));
final resultsProvider = FutureProvider.autoDispose.family<ClassResults, ({int classroomId, int period})>((ref, k) => ref.watch(repoProvider).results(k.classroomId, k.period));
final reportCardProvider = FutureProvider.autoDispose.family<ReportCard, ({int enrollmentId, int period})>((ref, k) => ref.watch(repoProvider).reportCard(k.enrollmentId, k.period));
final childReportCardProvider = FutureProvider.autoDispose.family<ReportCard, ({int enrollmentId, int period})>((ref, k) => ref.watch(repoProvider).childReportCard(k.enrollmentId, k.period));
final classTimetableProvider = FutureProvider.autoDispose.family<ClassTimetable, int>((ref, classroomId) => ref.watch(repoProvider).classTimetable(classroomId));
final myWeekProvider = FutureProvider.autoDispose<Week>((ref) => ref.watch(repoProvider).myWeek());
final childTimetableProvider = FutureProvider.autoDispose.family<Week, int>((ref, enrollmentId) => ref.watch(repoProvider).childTimetable(enrollmentId));
final upcomingCancellationsProvider = FutureProvider.autoDispose<List<CancelledSession>>((ref) => ref.watch(repoProvider).upcomingCancellations());
final teachersProvider = FutureProvider.autoDispose<List<TeacherRef>>((ref) => ref.watch(repoProvider).teachers());
final messagesProvider = FutureProvider.autoDispose.family<MessageLog, String?>((ref, status) => ref.watch(repoProvider).messages(status: status));
final billingProvider = FutureProvider.autoDispose<BillingInfo>((ref) => ref.watch(repoProvider).billing());
final adminSchoolsProvider = FutureProvider.autoDispose<List<AdminSchool>>((ref) => ref.watch(repoProvider).adminSchools());
final adminSchoolProvider = FutureProvider.autoDispose.family<AdminSchoolDetail, int>((ref, id) => ref.watch(repoProvider).adminSchool(id));
final childReportsProvider = FutureProvider.autoDispose.family<List<AbsenceReport>, int>((ref, id) => ref.watch(repoProvider).childAbsenceReports(id));

/// The school's logo (staff): fetched again only when `logo_version` changes. Null when the school has none.
final schoolLogoProvider = FutureProvider.autoDispose.family<Uint8List?, String?>((ref, version) => version == null ? Future.value(null) : ref.watch(repoProvider).schoolLogo());
final parentLogoProvider = FutureProvider.autoDispose.family<Uint8List?, ({int schoolId, String? version})>((ref, k) => k.version == null ? Future.value(null) : ref.watch(repoProvider).parentSchoolLogo(k.schoolId));
final childrenProvider = FutureProvider.autoDispose<List<ChildRow>>((ref) => ref.watch(repoProvider).children());
final remindersProvider = FutureProvider.autoDispose<List<ReminderItem>>((ref) => ref.watch(repoProvider).reminders());
