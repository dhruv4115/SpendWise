import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/session_provider.dart';
import '../security/secure_session_store.dart';
import 'api_config.dart';
import 'error_mapper.dart';

/// Long enough for a cold mobile network, short enough that a wedged request
/// surfaces as an error instead of an endless spinner.
const Duration connectTimeout = Duration(seconds: 10);
const Duration receiveTimeout = Duration(seconds: 10);

/// Attaches the bearer token to every outbound request.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._store);

  final SessionStore _store;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _store.readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

/// Debug-only request log.
///
/// Method, path, status and traceId only. Never headers — they carry the
/// bearer token — and never bodies, which carry transaction detail. Ids in the
/// path are redacted.
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor({void Function(String line)? log})
      : _log = log ?? debugPrint;

  final void Function(String line) _log;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      _log('→ ${options.method} ${redactPath(options.path)}');
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    if (kDebugMode) {
      _log(
        '← ${response.statusCode} ${response.requestOptions.method} '
        '${redactPath(response.requestOptions.path)}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      final traceId = parseErrorEnvelope(err.response?.data).traceId;
      _log(
        '← ${err.response?.statusCode ?? err.type.name} '
        '${err.requestOptions.method} ${redactPath(err.requestOptions.path)} '
        '[${traceId ?? '-'}]',
      );
    }
    handler.next(err);
  }
}

/// Drops the session the moment the server says the token is no good.
///
/// It does not retry and does not attempt a refresh: this API has no refresh
/// token, so the only correct response is to send the customer back to sign-in
/// and let the router guard do it.
class UnauthorisedInterceptor extends Interceptor {
  UnauthorisedInterceptor(this._onUnauthorised);

  /// Sign-in is the one endpoint where a 401 means "wrong password" rather
  /// than "your session ended", so it is exempt.
  static const String _signInPath = '/auth/login';

  final Future<void> Function() _onUnauthorised;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final isSignIn = err.requestOptions.path.endsWith(_signInPath);
    if (err.response?.statusCode == 401 && !isSignIn) {
      await _onUnauthorised();
    }
    handler.next(err);
  }
}

/// Builds the configured client. Split out from [dioProvider] so a test can
/// build one without a ProviderContainer.
Dio buildApiClient({
  required SessionStore store,
  required Future<void> Function() onUnauthorised,
  String baseUrl = ApiConfig.baseUrl,
  void Function(String line)? log,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      responseType: ResponseType.json,
      contentType: Headers.jsonContentType,
    ),
  );

  dio.interceptors.addAll([
    AuthInterceptor(store),
    LoggingInterceptor(log: log),
    UnauthorisedInterceptor(onUnauthorised),
  ]);

  return dio;
}

/// The transport underneath the client. Null means "use a real socket".
///
/// The seam exists so a test can exercise the production [dioProvider] — its
/// interceptors, its session store, its 401 handling — against a hand-written
/// adapter, instead of assembling a parallel client that could drift from it.
final Provider<HttpClientAdapter?> httpClientAdapterProvider =
    Provider<HttpClientAdapter?>((ref) => null);

/// The app's single HTTP client. Repositories depend on this; widgets never do.
final Provider<Dio> dioProvider = Provider<Dio>((ref) {
  final dio = buildApiClient(
    store: ref.watch(sessionStoreProvider),
    onUnauthorised: () => ref.read(sessionProvider.notifier).revoke(),
  );

  final adapter = ref.watch(httpClientAdapterProvider);
  if (adapter != null) dio.httpClientAdapter = adapter;

  ref.onDispose(dio.close);
  return dio;
});
