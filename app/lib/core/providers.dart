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
