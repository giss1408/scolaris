import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'errors.dart';
import 'models.dart';

/// Only the refresh token is stored on the phone (secure storage); the short access token lives in memory.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String refresh);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore();
  static const _key = 'refresh_token';
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read() => _s.read(key: _key);
  @override
  Future<void> write(String refresh) => _s.write(key: _key, value: refresh);
  @override
  Future<void> clear() => _s.delete(key: _key);
}

class MemoryTokenStore implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String refresh) async => value = refresh;
  @override
  Future<void> clear() async => value = null;
}

/// The platform auth service: the one place people sign in (phone + password). Throws raw DioExceptions, callers map them.
class AuthService {
  AuthService(this._dio);
  final Dio _dio;

  static String digits(String phone) => phone.replaceAll(RegExp(r'[\s.\-]'), '');

  Future<Map<String, dynamic>> login(String phone, String password) async {
    final r = await _dio.post<Map<String, dynamic>>('/v1/login', data: {'phone': digits(phone), 'password': password, 'product': Config.product, 'app': Config.authApp});
    return r.data!;
  }

  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final r = await _dio.post<Map<String, dynamic>>('/v1/refresh', data: {'refresh_token': refreshToken});
    return r.data!;
  }

  Future<void> activate(String phone, String code, String password) async {
    await _dio.post<Object?>('/v1/activate', data: {'phone': digits(phone), 'code': code.trim(), 'password': password});
  }

  Future<void> logout(String refreshToken, String access) async {
    await _dio.post<Object?>('/v1/logout', data: {'refresh_token': refreshToken}, options: Options(headers: {'Authorization': 'Bearer $access'}));
  }

  /// Password re-proved: a fresh token (`amr` says so) for sensitive money actions.
  Future<String> stepUp(String access, String password) async {
    final r = await _dio.post<Map<String, dynamic>>('/v1/step-up', data: {'password': password}, options: Options(headers: {'Authorization': 'Bearer $access'}));
    return r.data!['access_token'] as String;
  }

  Future<void> changePassword(String access, String current, String next) async {
    await _dio.post<Object?>('/v1/password/change', data: {'current_password': current, 'new_password': next}, options: Options(headers: {'Authorization': 'Bearer $access'}));
  }
}

enum SessionStatus { loading, signedOut, signedIn }

class SessionState {
  const SessionState(this.status, {this.me, this.notice});
  final SessionStatus status;
  final Me? me;

  /// Shown once on the sign-in page (e.g. "session expired").
  final String? notice;
}

final tokenStoreProvider = Provider<TokenStore>((_) => const SecureTokenStore());
final authDioProvider = Provider<Dio>((_) => Dio(BaseOptions(baseUrl: Config.authBase, connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15))));
final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(authDioProvider)));
final apiDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(baseUrl: Config.apiBase, connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 20)));
  final session = ref.read(sessionProvider.notifier);
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (o, h) {
      final t = session.access;
      if (t != null) o.headers['Authorization'] = 'Bearer $t';
      h.next(o);
    },
    onError: (e, h) async {
      // An expired access token: renew once at auth (single flight) and replay the request once.
      if (e.response?.statusCode == 401 && e.requestOptions.extra['retried'] != true && session.access != null) {
        if (await session.renew()) {
          final o = e.requestOptions..extra['retried'] = true;
          o.headers['Authorization'] = 'Bearer ${session.access}';
          try {
            return h.resolve(await dio.fetch<Object?>(o));
          } on DioException catch (e2) {
            return h.next(e2);
          }
        }
      }
      h.next(e);
    },
  ));
  return dio;
});

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  String? _access;
  String? _refresh;
  Future<bool>? _renewing;

  String? get access => _access;

  @override
  SessionState build() => const SessionState(SessionStatus.loading);

  AuthService get _auth => ref.read(authServiceProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);

  /// Called once at start-up: reopen the session from the stored refresh token, if any.
  Future<void> restore() async {
    final stored = await _store.read();
    if (stored == null) return _signedOut();
    _refresh = stored;
    if (!await renew()) return _signedOut();
    await _openProfile();
  }

  Future<void> signIn(String phone, String password) async {
    final Map<String, dynamic> t;
    try {
      t = await _auth.login(phone, password);
    } catch (e) {
      throw mapError(e);
    }
    if (t['must_change_password'] == true) throw AppError('password_change_required');
    await _adopt(t);
    await _openProfile();
  }

  Future<void> activate(String phone, String code, String password) async {
    try {
      await _auth.activate(phone, code, password);
    } catch (e) {
      throw mapError(e);
    }
    await signIn(phone, password);
  }

  /// Renews the access token at auth. One renewal at a time: the refresh token rotates, so two in parallel would end the session.
  Future<bool> renew() => _renewing ??= _doRenew().whenComplete(() => _renewing = null);

  Future<bool> _doRenew() async {
    final r = _refresh;
    if (r == null) return false;
    try {
      await _adopt(await _auth.refresh(r));
      return true;
    } catch (e) {
      final err = mapError(e);
      if (err.code == 'offline' || err.code == 'timeout' || err.code == 'server') return false; // keep the session: the network is down, not the login
      _signedOut(notice: 'Votre session a expiré. Connectez-vous à nouveau.');
      return false;
    }
  }

  Future<void> _adopt(Map<String, dynamic> t) async {
    _access = t['access_token'] as String;
    _refresh = t['refresh_token'] as String;
    await _store.write(_refresh!);
  }

  Future<void> _openProfile() async {
    try {
      final r = await ref.read(apiDioProvider).get<Map<String, dynamic>>('/v1/me');
      state = SessionState(SessionStatus.signedIn, me: Me.fromJson(r.data!));
    } catch (e) {
      final err = mapError(e);
      await _clear();
      state = SessionState(SessionStatus.signedOut, notice: userMessage(err));
      if (state.notice != null && err.code == 'offline') return;
      throw err;
    }
  }

  Future<void> stepUp(String password) async {
    try {
      _access = await _auth.stepUp(_access!, password);
    } catch (e) {
      throw mapError(e);
    }
  }

  Future<void> changePassword(String current, String next) async {
    try {
      await _auth.changePassword(_access!, current, next);
      await renew();
    } catch (e) {
      throw mapError(e);
    }
  }

  Future<void> signOut() async {
    final (r, a) = (_refresh, _access);
    if (r != null && a != null) {
      try {
        await _auth.logout(r, a);
      } catch (_) {/* signing out locally is what matters */}
    }
    _signedOut();
  }

  void _signedOut({String? notice}) {
    _clear();
    state = SessionState(SessionStatus.signedOut, notice: notice);
  }

  Future<void> _clear() async {
    _access = null;
    _refresh = null;
    await _store.clear();
  }
}
