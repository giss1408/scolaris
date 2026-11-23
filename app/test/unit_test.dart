import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scolaris/core/errors.dart';
import 'package:scolaris/core/money.dart';
import 'package:scolaris/core/repo.dart';
import 'package:scolaris/core/session.dart';
import 'package:scolaris/core/strings.dart';

DioException dio(int status, Object? data) => DioException(requestOptions: RequestOptions(path: '/x'), response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: status, data: data));

void main() {
  test('FCFA is whole numbers with non-breaking thousands', () {
    expect(formatFcfa(0), '0 FCFA');
    expect(formatFcfa(150000), '150 000 FCFA');
    expect(formatFcfa(1250000, unit: false), '1 250 000');
    expect(formatFcfa(-5000), '-5 000 FCFA');
  });

  test('typed amounts are parsed from any grouping', () {
    expect(parseFcfa('150 000'), 150000);
    expect(parseFcfa('150000 FCFA'), 150000);
    expect(parseFcfa('1 250 000'), 1250000);
    expect(parseFcfa(''), isNull);
  });

  test('server codes become readable French, never raw text', () {
    expect(userMessage(dio(401, {'detail': 'invalid_credentials'})), 'Numéro ou mot de passe incorrect.');
    expect(userMessage(dio(409, {'detail': 'matricule_already_used'})), contains('matricule'));
    expect(userMessage(dio(403, {'detail': 'something_new'})), contains('fonction'));
    expect(userMessage(dio(500, 'boom')), contains('de notre côté'));
    expect(userMessage(DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError)), contains('connexion'));
    expect(userMessage(StateError('secret internals')), isNot(contains('secret')));
  });

  test('step-up and ended sessions are recognised', () {
    expect(mapError(dio(403, {'detail': 'step_up_required'})).needsStepUp, isTrue);
    expect(mapError(dio(403, {'detail': 'session_ended'})).needsStepUp, isTrue);
    expect(mapError(dio(404, {'detail': 'not_found'})).needsStepUp, isFalse);
  });

  test('phone digits are sent without spaces', () {
    expect(AuthService.digits('07 01 02 03 04'), '0701020304');
    expect(AuthService.digits('+225 07-01-02-03-04'), '+2250701020304');
  });

  test('idempotency keys are random and long enough', () {
    final a = newIdempotencyKey(), b = newIdempotencyKey();
    expect(a, isNot(b));
    expect(a.length, 32);
  });

  test('new student payload: only what was filled, parent is the financial contact', () {
    final j = NewStudent(lastName: ' Kouassi ', firstNames: 'Aya', sex: 'F', classroomId: 3, parentName: 'Paul', parentPhone: '07 01 02 03 04', optin: true, options: ['cantine'], matricule: ' ').toJson();
    expect(j['last_name'], 'Kouassi');
    expect(j.containsKey('matricule_mena'), isFalse);
    expect((j['contacts']! as List).single, containsPair('phone', '0701020304'));
    expect((j['contacts']! as List).single, containsPair('financial_responsible', true));
    expect(j['enrollment'], {'classroom_id': 3, 'options': ['cantine']});
    expect(S.lateDays(1), 'Retard de 1 jour');
    expect(S.lateDays(12), 'Retard de 12 jours');
  });
}
