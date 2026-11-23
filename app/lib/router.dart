import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/logo.dart';
import 'core/session.dart';
import 'features/auth/login_page.dart';
import 'features/home/shell_page.dart';
import 'features/money/receipt_page.dart';
import 'features/setup/classes_page.dart';
import 'features/setup/fees_page.dart';
import 'features/setup/team_page.dart';
import 'features/students/student_detail_page.dart';
import 'features/students/student_form_page.dart';

/// Re-runs the redirect when the session changes (signed in / out).
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _SessionListenable(ref);
  return GoRouter(
    refreshListenable: listenable,
    initialLocation: '/',
    redirect: (context, state) {
      final status = ref.read(sessionProvider).status;
      final atLogin = state.matchedLocation == '/login';
      if (status == SessionStatus.loading) return state.matchedLocation == '/splash' ? null : '/splash';
      if (status == SessionStatus.signedOut) return atLogin ? null : '/login';
      return (atLogin || state.matchedLocation == '/splash') ? '/' : null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const Scaffold(body: Center(child: ScolarisLogo(size: 96)))),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/', builder: (_, __) => const ShellPage()),
      GoRoute(path: '/students/new', builder: (_, __) => const StudentFormPage()),
      GoRoute(
        path: '/students/:id',
        builder: (_, s) => StudentDetailPage(
          studentId: int.parse(s.pathParameters['id']!),
          enrollmentId: int.tryParse(s.uri.queryParameters['enrollment'] ?? '') ?? 0,
          classroom: s.uri.queryParameters['classroom'] ?? '',
        ),
      ),
      GoRoute(path: '/receipt/:id', builder: (_, s) => ReceiptPage(paymentId: int.parse(s.pathParameters['id']!), justPaid: s.uri.queryParameters['new'] == '1')),
      GoRoute(path: '/classes', builder: (_, __) => const ClassesPage()),
      GoRoute(path: '/fees', builder: (_, __) => const FeesPage()),
      GoRoute(path: '/team', builder: (_, __) => const TeamPage()),
    ],
  );
});
