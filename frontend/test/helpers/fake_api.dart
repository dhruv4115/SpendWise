import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// What the app actually sent, captured for assertions.
class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
    required this.body,
  });

  final String method;

  /// Path only, without the query string.
  final String path;
  final Map<String, Object?> query;

  /// Header names are lower-cased, because Dio does not normalise them.
  final Map<String, String> headers;

  /// Decoded JSON when the body was JSON, otherwise the raw string.
  final Object? body;

  String? get idempotencyKey => headers['idempotency-key'];
  String? get authorization => headers['authorization'];

  Map<String, Object?> get jsonBody =>
      body is Map<String, Object?> ? body! as Map<String, Object?> : const {};

  @override
  String toString() => '$method $path';
}

/// A hand-written Dio adapter: no mocking package, no real socket.
///
/// Register what the server should say, run the code under test, then assert
/// on [requests].
///
/// ```dart
/// final fake = FakeApi()
///   ..on('GET', '/transactions', body: {'items': [], 'nextCursor': null})
///   ..respondError('PUT', '/budgets',
///       status: 422, code: 'VALIDATION_FAILED', message: 'Check the amount.');
/// dio.httpClientAdapter = fake;
/// ```
class FakeApi implements HttpClientAdapter {
  final List<RecordedRequest> requests = [];
  final Map<String, List<_Route>> _routes = {};

  bool _closed = false;

  /// True once [close] has been called, so a test can assert the client is
  /// disposed with its provider.
  bool get isClosed => _closed;

  /// Registers a successful JSON response.
  ///
  /// [times] limits how often this route answers; once used up, the next
  /// matching route takes over. [delay] simulates a slow network.
  void on(
    String method,
    String path, {
    int status = 200,
    Object? body,
    Map<String, String> headers = const {},
    Duration? delay,
    int? times,
  }) {
    _add(
      method,
      path,
      _Route(
        status: status,
        payload: body == null ? '' : jsonEncode(body),
        contentType: Headers.jsonContentType,
        headers: headers,
        delay: delay,
        remaining: times,
      ),
    );
  }

  /// Registers a failure in the server's standard error envelope.
  void respondError(
    String method,
    String path, {
    required int status,
    required String code,
    String message = 'Something went wrong.',
    Map<String, String> details = const {},
    String traceId = '11111111-2222-3333-4444-555555555555',
    Duration? delay,
    int? times,
  }) {
    _add(
      method,
      path,
      _Route(
        status: status,
        payload: jsonEncode({
          'error': {
            'code': code,
            'message': message,
            'details': details,
            'traceId': traceId,
          },
        }),
        contentType: Headers.jsonContentType,
        delay: delay,
        remaining: times,
      ),
    );
  }

  /// Registers a response that arrives only after [delay] — for asserting that
  /// a loading state is rendered, or that a timeout fires.
  void respondAfter(
    String method,
    String path,
    Duration delay, {
    int status = 200,
    Object? body,
  }) {
    on(method, path, status: status, body: body, delay: delay);
  }

  /// Fails the *next* matching call only; the call after it falls through to
  /// whatever else is registered. Use it to drive a retry.
  void failOnce(
    String method,
    String path, {
    int status = 503,
    String code = 'UPSTREAM_UNAVAILABLE',
    String message = 'The bank is unavailable.',
  }) {
    _addFirst(
      method,
      path,
      _Route(
        status: status,
        payload: jsonEncode({
          'error': {
            'code': code,
            'message': message,
            'details': const <String, String>{},
            'traceId': 'once-0000-0000-0000-000000000000',
          },
        }),
        contentType: Headers.jsonContentType,
        remaining: 1,
      ),
    );
  }

  /// Registers a non-JSON body, such as the HTML error page a proxy returns.
  void respondRaw(
    String method,
    String path, {
    required int status,
    required String body,
    String contentType = 'text/html; charset=utf-8',
  }) {
    _add(
      method,
      path,
      _Route(status: status, payload: body, contentType: contentType),
    );
  }

  /// Every request sent to [path], in order.
  List<RecordedRequest> requestsFor(String method, String path) => requests
      .where((r) => r.method == method.toUpperCase() && r.path == path)
      .toList(growable: false);

  void reset() {
    requests.clear();
    _routes.clear();
  }

  void _add(String method, String path, _Route route) =>
      _routes.putIfAbsent(_key(method, path), () => []).add(route);

  void _addFirst(String method, String path, _Route route) =>
      _routes.putIfAbsent(_key(method, path), () => []).insert(0, route);

  String _key(String method, String path) => '${method.toUpperCase()} $path';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    requests.add(
      RecordedRequest(
        method: options.method.toUpperCase(),
        path: uri.path,
        query: Map<String, Object?>.from(uri.queryParameters),
        headers: {
          for (final entry in options.headers.entries)
            entry.key.toLowerCase(): '${entry.value}',
        },
        body: await _readBody(options, requestStream),
      ),
    );

    final route = _take(options.method, uri.path);
    if (route == null) {
      throw StateError(
        'FakeApi has no route for ${options.method.toUpperCase()} ${uri.path}. '
        'Registered: ${_routes.keys.join(', ')}',
      );
    }

    if (route.delay != null) await Future<void>.delayed(route.delay!);

    return ResponseBody.fromString(
      route.payload,
      route.status,
      headers: {
        Headers.contentTypeHeader: [route.contentType],
        for (final entry in route.headers.entries) entry.key: [entry.value],
      },
    );
  }

  _Route? _take(String method, String path) {
    final routes = _routes[_key(method, path)];
    if (routes == null || routes.isEmpty) return null;

    final route = routes.first;
    if (route.remaining == null) return route;

    route.remaining = route.remaining! - 1;
    if (route.remaining! <= 0) routes.removeAt(0);
    return route;
  }

  Future<Object?> _readBody(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) async {
    if (requestStream == null) return null;

    final bytes = <int>[];
    await for (final chunk in requestStream) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return null;

    final text = utf8.decode(bytes);
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  @override
  void close({bool force = false}) => _closed = true;
}

class _Route {
  _Route({
    required this.status,
    required this.payload,
    required this.contentType,
    this.headers = const {},
    this.delay,
    this.remaining,
  });

  final int status;
  final String payload;
  final String contentType;
  final Map<String, String> headers;
  final Duration? delay;

  /// Null means "answer for ever".
  int? remaining;
}
