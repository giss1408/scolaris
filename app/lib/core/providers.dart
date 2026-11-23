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
final myWeekProvider = FutureProvider.autoDispose<List<Slot>>((ref) => ref.watch(repoProvider).myWeek());
final childTimetableProvider = FutureProvider.autoDispose.family<List<Slot>, int>((ref, enrollmentId) => ref.watch(repoProvider).childTimetable(enrollmentId));
final childrenProvider = FutureProvider.autoDispose<List<ChildRow>>((ref) => ref.watch(repoProvider).children());
final remindersProvider = FutureProvider.autoDispose<List<ReminderItem>>((ref) => ref.watch(repoProvider).reminders());
