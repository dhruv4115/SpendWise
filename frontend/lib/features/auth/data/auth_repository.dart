import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/error_mapper.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/security/secure_session_store.dart';
import '../domain/session.dart';

/// Everything the app does with `/auth`, and the only place the stored session
/// is written or cleared.
///
/// The provider layer never touches [SessionStore] directly: keeping both the
/// network call and the keystore behind one repository means "signed in" can
/// never mean one thing on disk and another in memory.
///
/// Throws [BankError] and nothing else — [DioException] is converted here, at
/// the repository border, and never escapes upwards.
class AuthRepository {
  AuthRepository({required Dio dio, required SessionStore store})
      : _dio = dio,
        _store = store;

  static const String loginPath = '/auth/login';

  final Dio _dio;
  final SessionStore _store;

  /// Exchanges credentials for a bearer token and remembers it.
  ///
  /// [idempotencyKey] is owned by the caller — the login controller holds one
  /// key per sign-in attempt, so pressing "Try again" after a dropped response
  /// replays the original outcome instead of minting a second token.
  Future<Session> login({
    required String email,
    required String password,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        loginPath,
        data: {'email': email, 'password': password},
        options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
      );

      final session = _sessionFrom(response.data);
      await _store.write(session);
      return session;
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  /// Forgets the session. Local only: this API has no server-side sign-out.
  Future<void> logout() => _store.clear();

  /// The remembered session, or null when there is none. Read once on boot.
  Future<Session?> currentSession() => _store.read();

  Session _sessionFrom(Object? data) {
    if (data is! Map) {
      throw const UnknownError(code: 'MALFORMED_LOGIN_RESPONSE');
    }
    try {
      return Session.fromJson(Map<String, Object?>.from(data));
    } on FormatException {
      // The server answered 200 with something unusable. A parse failure is
      // not a customer-facing detail, so it becomes the generic error rather
      // than leaking the exception text into the banner.
      throw const UnknownError(code: 'MALFORMED_LOGIN_RESPONSE');
    }
  }
}

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
  (ref) => AuthRepository(
    dio: ref.watch(dioProvider),
    store: ref.watch(sessionStoreProvider),
  ),
);
