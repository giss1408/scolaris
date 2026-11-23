import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/errors.dart';
import 'package:scolaris/core/models.dart';
import 'package:scolaris/features/admin/admin_pages.dart';
import 'package:scolaris/features/auth/login_page.dart';
import 'package:scolaris/features/billing/billing_page.dart';
import 'package:scolaris/features/home/shell_page.dart';

import 'helpers.dart';

void main() {
  void phone(WidgetTester t, {double h = 2600, double w = 390}) => t.view
    ..physicalSize = Size(w, h)
    ..devicePixelRatio = 1.0;

  Me withBanner(String role, BillingBanner? b) {
    final m = meWith(role);
    return Me(staffId: m.staffId, name: m.name, role: m.role, schoolName: m.schoolName, city: m.city, yearId: m.yearId, yearLabel: m.yearLabel, levels: m.levels, feeKinds: m.feeKinds, methods: m.methods, banner: b);
  }

  testWidgets('a late subscription shows a banner at the top for the director and the secretary only', (t) async {
    phone(t);
    const late = BillingBanner(level: 'late', title: 'Rappel : mensualité Scolaris en retard', text: 'En retard', unseen: 1);
    for (final role in ['director', 'secretary']) {
      await t.pumpWidget(harness(const ShellPage(), me: withBanner(role, late)));
      await t.pumpAndSettle();
      expect(find.byType(BillingBannerBar), findsOneWidget, reason: role);
      expect(find.textContaining('Rappel : mensualité Scolaris en retard.'), findsOneWidget, reason: role);
    }
    for (final role in ['teacher', 'accountant']) {
      await t.pumpWidget(harness(const ShellPage(), me: withBanner(role, null)));
      await t.pumpAndSettle();
      expect(find.byType(BillingBannerBar), findsNothing, reason: role);
    }
    await t.pumpWidget(harness(const ShellPage(), me: withBanner('director', const BillingBanner(level: 'info', title: '', text: '', unseen: 2))));
    await t.pumpAndSettle();
    expect(find.byType(BillingBannerBar), findsNothing); // only unread notices: no alarm
  });

  testWidgets('a final notice names the date; the banner is readable in words, not only colour', (t) async {
    phone(t);
    await t.pumpWidget(harness(const ShellPage(), me: withBanner('director', BillingBanner(level: 'final', title: 'Dernier avis avant suspension', text: 'x', blockOn: DateTime(2026, 12, 10)))));
    await t.pumpAndSettle();
    expect(find.text('Dernier avis avant suspension. Suspension le 10/12/2026.'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('a suspended school: the direction sees why and what is owed, nothing else is open', (t) async {
    phone(t);
    final blocked = withBanner('director', const BillingBanner(level: 'blocked', title: 'Accès suspendu', text: 'Suspendu pour impayé.'));
    await t.pumpWidget(harness(const ShellPage(), me: blocked));
    await t.pumpAndSettle();
    expect(find.text('Accès suspendu'), findsWidgets);
    expect(find.textContaining('Réglez la mensualité en retard'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing); // no tab: students, money and grades are closed
    expect(find.text('100 000 FCFA'), findsOneWidget); // what is owed
    expect(find.byTooltip('Se déconnecter'), findsOneWidget);
  });

  testWidgets('the subscription page: what is owed, the notices, and "J\'ai lu" tells the team', (t) async {
    phone(t);
    final session = FakeSession(meWith('secretary'));
    final repo = FakeRepo();
    await t.pumpWidget(harness(const BillingPage(), me: null, session: session, repo: repo));
    await t.pumpAndSettle();
    expect(find.text('2 mensualités en retard · 49 jours'), findsOneWidget);
    expect(find.text('50 000 FCFA'), findsOneWidget);
    expect(find.text('Prochaine échéance : 05/12/2026'), findsOneWidget);
    expect(find.text('Nouveau'), findsOneWidget);
    await t.tap(find.text("J'ai lu"));
    await t.pumpAndSettle();
    expect(repo.seenNotices, [7]);
    expect(session.refreshes, 1); // the banner's unread count is recomputed
  });

  testWidgets('a school without a subscription says so; a paid-up one shows À jour', (t) async {
    phone(t);
    final none = FakeRepo()..billingInfo = const BillingInfo(status: 'active');
    await t.pumpWidget(harness(const BillingPage(), me: meWith('director'), repo: none));
    await t.pumpAndSettle();
    expect(find.textContaining("Aucun abonnement n'est défini"), findsOneWidget);
    final ok = FakeRepo()..billingInfo = BillingInfo(status: 'active', standing: Standing(monthlyAmount: 50000, billingDay: 5, remaining: 0, overdueMonths: 0, oldestLateDays: 0, late: false, nextDue: DateTime(2026, 12, 5)));
    await t.pumpWidget(harness(const BillingPage(), me: meWith('director'), repo: ok));
    await t.pumpAndSettle();
    expect(find.text('À jour'), findsOneWidget);
  });

  testWidgets('sign-in for the Scolaris team asks for the authenticator code and sends it', (t) async {
    phone(t, h: 2400);
    final session = FakeSession(null);
    await t.pumpWidget(harness(const LoginPage(), me: null, session: session));
    await t.tap(find.text('Équipe Scolaris'));
    await t.pumpAndSettle();
    expect(find.text("Code d'authentification"), findsOneWidget);
    expect(find.text('Créer mon compte'), findsNothing); // no sign-up and no activation for the team
    expect(find.text("J'ai reçu un code d'activation"), findsNothing);
    await t.enterText(find.byType(TextFormField).at(0), '07 01 02 03 04');
    await t.enterText(find.byType(TextFormField).at(1), 'MonMotDePasse2026');
    await t.tap(find.text('Se connecter').last);
    await t.pumpAndSettle();
    expect(find.text('Le code a 6 chiffres'), findsOneWidget);
    expect(session.calls, isEmpty);
    await t.enterText(find.byType(TextFormField).at(2), '123456');
    await t.tap(find.text('Se connecter').last);
    await t.pumpAndSettle();
    expect(session.calls, ['signIn parent=false admin=true totp=123456']);
  });

  testWidgets('the team sees every school, the late ones with their debt', (t) async {
    phone(t);
    await t.pumpWidget(harness(const AdminHome(), me: null, session: FakeSession(null, admin: true)));
    await t.pumpAndSettle();
    expect(find.text('Ecole Bloquée'), findsOneWidget);
    expect(find.text('Bloquée'), findsOneWidget);
    expect(find.text('En retard'), findsOneWidget);
    expect(find.text('À jour'), findsOneWidget);
    expect(find.textContaining('3 mensualités en retard · 150 000 FCFA'), findsOneWidget);
    final first = t.getTopLeft(find.text('Ecole Bloquée')).dy;
    final last = t.getTopLeft(find.text("Ecole A l'heure")).dy;
    expect(first < last, isTrue); // the server's order is kept: blocked, then late, then up to date
  });

  testWidgets('a late school: reminder, final notice with its date, block; reminders need a confirmation', (t) async {
    phone(t, h: 3200);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const AdminSchoolPage(schoolId: 2), me: null, session: FakeSession(null, admin: true), repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Reste à payer'), findsOneWidget);
    expect(find.text('2 mensualités en retard · 40 jours'), findsWidgets);
    expect(find.text('Vu par 1 sur 2'), findsOneWidget); // the team sees how many of the direction and secretary read the reminder
    expect(find.text("Rétablir l'accès"), findsNothing);
    await t.tap(find.text('Envoyer un rappel'));
    await t.pumpAndSettle();
    expect(find.textContaining("verront ce rappel dans l'application"), findsOneWidget);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(repo.adminCalls, isEmpty);
    await t.tap(find.text('Envoyer un rappel'));
    await t.pumpAndSettle();
    await t.tap(find.text('Envoyer').last);
    await t.pumpAndSettle();
    expect(repo.adminCalls, ['notice reminder']);
    await t.tap(find.text('Dernier avis'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(repo.adminCalls.last, startsWith('notice final_notice '));
    final announced = DateTime.parse(repo.adminCalls.last.split(' ').last);
    expect(announced.isAfter(DateTime.now().add(const Duration(days: 6))), isTrue); // a block date at least a week ahead
  });

  testWidgets('blocking needs a reason and says what it does; a refusal from the server is shown in words', (t) async {
    phone(t, h: 3200);
    final repo = FakeRepo()..adminError = AppError('reminders_required', status: 400);
    await t.pumpWidget(harness(const AdminSchoolPage(schoolId: 2), me: null, session: FakeSession(null, admin: true), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text("Bloquer l'école"));
    await t.pumpAndSettle();
    expect(find.textContaining("n'auront plus accès à Scolaris"), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'ab'); // too short: nothing is sent and the dialog stays open
    await t.tap(find.widgetWithText(TextButton, "Bloquer l'école"));
    await t.pumpAndSettle();
    expect(repo.adminCalls, isEmpty);
    expect(find.textContaining("n'auront plus accès à Scolaris"), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'Impayé depuis deux mois');
    await t.tap(find.widgetWithText(TextButton, "Bloquer l'école"));
    await t.pumpAndSettle();
    expect(find.text("Envoyez d'abord des rappels dans l'application."), findsOneWidget); // the server's refusal, in words
    expect(repo.adminCalls, isEmpty);
    repo.adminError = null;
    await t.pumpAndSettle(const Duration(seconds: 5)); // the message goes away
    await t.tap(find.text("Bloquer l'école"));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Impayé depuis deux mois');
    await t.tap(find.widgetWithText(TextButton, "Bloquer l'école"));
    await t.pumpAndSettle();
    expect(repo.adminCalls, ['block Impayé depuis deux mois']);
  });

  testWidgets('a blocked school offers to restore access, asking for password AND authenticator code again', (t) async {
    phone(t, h: 3200);
    final session = FakeSession(null, admin: true);
    final repo = FakeRepo()
      ..stepUpOnce = true
      ..adminDetail = AdminSchoolDetail(school: FakeRepo().adminList[0], standing: FakeRepo().adminList[0].standing, reminders: 2, finalNotices: 1, blockedReason: 'Impayé', notices: const [], payments: const []);
    await t.pumpWidget(harness(const AdminSchoolPage(schoolId: 1), me: null, session: session, repo: repo));
    await t.pumpAndSettle();
    expect(find.text('Accès suspendu'), findsOneWidget);
    expect(find.text('Motif : Impayé'), findsOneWidget);
    expect(find.text("Bloquer l'école"), findsNothing);
    await t.tap(find.text("Rétablir l'accès").first);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, "Rétablir l'accès"));
    await t.pumpAndSettle();
    expect(find.text('Confirmer votre identité'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'MonMotDePasse2026');
    await t.enterText(find.widgetWithText(TextField, "Code d'authentification"), '654321');
    await t.tap(find.widgetWithText(TextButton, 'Confirmer'));
    await t.pumpAndSettle();
    expect(session.stepUps.single, (password: 'MonMotDePasse2026', totp: '654321'));
    expect(repo.adminCalls, ['unblock']); // retried once, after the proof
  });

  testWidgets('recording a payment: prefilled with what is owed, step-up on demand, then recorded', (t) async {
    phone(t, h: 3200);
    final session = FakeSession(null, admin: true);
    final repo = FakeRepo()..stepUpOnce = true;
    await t.pumpWidget(harness(const AdminSchoolPage(schoolId: 2), me: null, session: session, repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text('Enregistrer un paiement'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Montant (FCFA)'), findsOneWidget);
    expect(find.text('60 000'), findsOneWidget); // the 60 000 FCFA still owed
    await t.tap(find.widgetWithText(FilledButton, 'Enregistrer un paiement'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400)); // the button spins while the confirmation dialog is open: do not wait for it to settle
    await t.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'MonMotDePasse2026');
    await t.enterText(find.widgetWithText(TextField, "Code d'authentification"), '111222');
    await t.tap(find.widgetWithText(TextButton, 'Confirmer'));
    await t.pumpAndSettle();
    expect(repo.adminCalls, ['payment 60000 wave']);
    expect(session.stepUps, hasLength(1));
  });

  testWidgets('setting a subscription: a day outside 1-28 is refused in the form, a valid one is sent', (t) async {
    phone(t, h: 3200);
    final repo = FakeRepo();
    await t.pumpWidget(harness(const AdminSchoolPage(schoolId: 2), me: null, session: FakeSession(null, admin: true), repo: repo));
    await t.pumpAndSettle();
    await t.tap(find.text("Définir l'abonnement"));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Jour de paiement (1 à 28)'), '31');
    await t.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await t.pumpAndSettle();
    expect(find.text('Indiquez un montant et un jour entre 1 et 28.'), findsOneWidget);
    expect(repo.adminCalls, isEmpty);
    await t.enterText(find.widgetWithText(TextField, 'Jour de paiement (1 à 28)'), '5');
    await t.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await t.pumpAndSettle();
    expect(repo.adminCalls, ['subscription 30000/5']);
  });

  testWidgets('a school with no subscription: told it is never late, no chase buttons', (t) async {
    phone(t);
    final repo = FakeRepo();
    repo.adminDetail = const AdminSchoolDetail(school: AdminSchool(id: 9, name: 'Ecole Pilote', status: 'active', reminders: 0, finalNotices: 0), notices: [], payments: [], reminders: 0, finalNotices: 0);
    await t.pumpWidget(harness(const AdminSchoolPage(schoolId: 9), me: null, session: FakeSession(null, admin: true), repo: repo));
    await t.pumpAndSettle();
    expect(find.text("Pas d'abonnement défini : cette école n'est jamais en retard."), findsOneWidget);
    for (final b in ['Enregistrer un paiement', 'Envoyer un rappel', "Bloquer l'école"]) {
      expect(find.text(b), findsNothing, reason: b);
    }
  });

  test('messages for the new refusals are readable; the server sentence wins when there is one', () {
    DioException e(String code, [String? message]) => DioException(requestOptions: RequestOptions(path: '/x'), response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: 403, data: {'detail': code, if (message != null) 'message': message}));
    expect(userMessage(e('school_blocked', "L'accès de votre établissement est suspendu. Contactez la direction.")), contains('suspendu'));
    expect(userMessage(e('school_blocked')), contains('suspendu'));
    expect(userMessage(e('block_date_not_reached')), contains("pas encore arrivée"));
    expect(userMessage(e('final_notice_required')), contains('dernier avis'));
    expect(userMessage(e('image_too_large')), contains('512 Ko'));
    expect(userMessage(e('totp_required')), contains("code d'authentification"));
    expect(userMessage(e('only_today', 'Vous pouvez faire l\'appel d\'aujourd\'hui seulement ; demandez à la direction pour un autre jour.')), contains('demandez à la direction'));
  });

  testWidgets('no overflow at 320 px, text x2: subscription and team screens', (t) async {
    phone(t, h: 3200, w: 320);
    final problems = <String>[];
    final director = withBanner('director', const BillingBanner(level: 'blocked', title: 'Accès suspendu', text: 'x'));
    for (final (page, admin) in <(Widget, bool)>[(const BillingPage(), false), (const BlockedPage(), false), (const AdminHome(), true), (const AdminSchoolPage(schoolId: 2), true)]) {
      await t.pumpWidget(harness(page, me: director, session: admin ? FakeSession(null, admin: true) : null, textScale: 2.0));
      await t.pumpAndSettle();
      final ex = t.takeException();
      if (ex != null) problems.add('${page.runtimeType}: ${ex.toString().split('\n').first}');
    }
    expect(problems, isEmpty);
  });
}
