import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/network/idempotency.dart';
import 'package:spendwise/core/security/secure_session_store.dart';

import '../helpers/container.dart';
import '../helpers/fake_api.dart';

const Session _session = Session(
  token: 'tok_abcdef0123456789',
  userId: 'usr_123456789abc',
  userName: 'Asha Rao',
  email: 'asha@example.com',
);

/// In-memory stand-in for the keystore, which does not exist in a unit test.
class FakeSessionStore implements SessionStore {
  FakeSessionStore({Session? session}) : _session = session;

  Session? _session;
  int clearCount = 0;
  int writeCount = 0;

  @override
  Future<Session?> read() async => _session;

  @override
  Future<String?> readToken() async => _session?.token;

  @override
  Future<void> write(Session session) async {
    writeCount += 1;
    _session = session;
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
    _session = null;
  }
}

Dio clientFor(
  FakeApi fake, {
  SessionStore? store,
  Future<void> Function()? onUnauthorised,
  void Function(String)? log,
}) {
  final dio = buildApiClient(
    store: store ?? FakeSessionStore(),
    onUnauthorised: onUnauthorised ?? () async {},
    log: log ?? (_) {},
  );
  dio.httpClientAdapter = fake;
  return dio;
}

void main() {
  group('BaseOptions', () {
    test('uses the configured base URL and 10s timeouts', () {
      final dio = clientFor(FakeApi());

      expect(dio.options.baseUrl, isNotEmpty);
      expect(dio.options.connectTimeout, const Duration(seconds: 10));
      expect(dio.options.receiveTimeout, const Duration(seconds: 10));
    });

    test('registers auth, logging and unauthorised in that order', () {
      final dio = clientFor(FakeApi());

      // Dio installs its own content-type interceptor first; only the relative
      // order of ours is ours to guarantee.
      const ours = {
        AuthInterceptor,
        LoggingInterceptor,
        UnauthorisedInterceptor,
      };
      final order = dio.interceptors
          .map((i) => i.runtimeType)
          .where(ours.contains)
          .toList();

      expect(order, [
        AuthInterceptor,
        LoggingInterceptor,
        UnauthorisedInterceptor,
      ]);
    });
  });

  group('AuthInterceptor', () {
    test('attaches the bearer token from the session store', () async {
      final fake = FakeApi()..on('GET', '/transactions', body: {'items': []});
      final dio = clientFor(fake, store: FakeSessionStore(session: _session));

      await dio.get<Object?>('/transactions');

      expect(fake.requests.single.authorization, 'Bearer ${_session.token}');
    });

    test('sends no Authorization header when signed out', () async {
      final fake = FakeApi()..on('GET', '/categories', body: {'items': []});
      final dio = clientFor(fake, store: FakeSessionStore());

      await dio.get<Object?>('/categories');

      expect(fake.requests.single.authorization, isNull);
    });

    test('picks up a token written after the client was built', () async {
      final store = FakeSessionStore();
      final fake = FakeApi()..on('GET', '/summary', body: {}, times: 2);
      final dio = clientFor(fake, store: store);

      await dio.get<Object?>('/summary');
      await store.write(_session);
      await dio.get<Object?>('/summary');

      expect(fake.requests.first.authorization, isNull);
      expect(fake.requests.last.authorization, 'Bearer ${_session.token}');
    });
  });

  group('LoggingInterceptor', () {
    test('logs method, path and status but never headers or bodies', () async {
      final lines = <String>[];
      final fake = FakeApi()
        ..on('POST', '/budgets', body: {'category': 'food'});
      final dio = clientFor(
        fake,
        store: FakeSessionStore(session: _session),
        log: lines.add,
      );

      await dio.post<Object?>(
        '/budgets',
        data: {'category': 'food', 'limitPaise': 450000},
        options: Options(headers: {idempotencyKeyHeader: newIdempotencyKey()}),
      );

      expect(lines, isNotEmpty);
      final logged = lines.join('\n');
      expect(logged, contains('POST /budgets'));
      expect(logged, contains('200'));
      expect(logged, isNot(contains('Bearer')));
      expect(logged, isNot(contains(_session.token)));
      expect(logged, isNot(contains('Idempotency')));
      expect(logged, isNot(contains('limitPaise')));
    });

    test('redacts ids in the path', () async {
      final lines = <String>[];
      final fake = FakeApi()
        ..on('GET', '/transactions/txn_202609_0040', body: {'id': 'x'});
      final dio = clientFor(fake, log: lines.add);

      await dio.get<Object?>('/transactions/txn_202609_0040');

      final logged = lines.join('\n');
      expect(logged, contains('/transactions/:id'));
      expect(logged, isNot(contains('txn_202609_0040')));
    });

    test('logs the traceId when a request fails', () async {
      final lines = <String>[];
      final fake = FakeApi()
        ..respondError(
          'GET',
          '/summary',
          status: 503,
          code: 'UPSTREAM_UNAVAILABLE',
          message: 'The bank is unavailable.',
          traceId: 'trace-abc',
        );
      final dio = clientFor(fake, log: lines.add);

      await expectLater(
        dio.get<Object?>('/summary'),
        throwsA(isA<DioException>()),
      );

      expect(lines.join('\n'), contains('trace-abc'));
    });
  });

  group('UnauthorisedInterceptor', () {
    test('signals on 401 and does not retry', () async {
      var signals = 0;
      final fake = FakeApi()
        ..respondError(
          'GET',
          '/transactions',
          status: 401,
          code: 'AUTH_TOKEN_INVALID',
          message: 'Session ended.',
        );
      final dio = clientFor(fake, onUnauthorised: () async => signals += 1);

      await expectLater(
        dio.get<Object?>('/transactions'),
        throwsA(isA<DioException>()),
      );

      expect(signals, 1);
      expect(fake.requests, hasLength(1), reason: 'must not retry');
    });

    test('ignores every other failure', () async {
      var signals = 0;
      final fake = FakeApi()
        ..respondError('GET', '/summary', status: 500, code: 'INTERNAL_ERROR');
      final dio = clientFor(fake, onUnauthorised: () async => signals += 1);

      await expectLater(
        dio.get<Object?>('/summary'),
        throwsA(isA<DioException>()),
      );

      expect(signals, 0);
    });
  });

  group('dioProvider', () {
    test('wires the session store into the client', () async {
      final store = FakeSessionStore(session: _session);
      final container = makeContainer(
        overrides: [sessionStoreProvider.overrideWithValue(store)],
      );

      final fake = FakeApi()..on('GET', '/categories', body: {'items': []});
      final dio = container.read(dioProvider)..httpClientAdapter = fake;

      await dio.get<Object?>('/categories');

      expect(fake.requests.single.authorization, 'Bearer ${_session.token}');
    });

    test('a 401 clears the stored session and empties the notifier', () async {
      final store = FakeSessionStore(session: _session);
      final container = makeContainer(
        overrides: [sessionStoreProvider.overrideWithValue(store)],
      );
      readAndKeepAlive(container, sessionProvider);
      expect(await container.read(sessionProvider.future), _session);

      final fake = FakeApi()
        ..respondError(
          'GET',
          '/transactions',
          status: 401,
          code: 'AUTH_TOKEN_INVALID',
          message: 'Session ended.',
        );
      final dio = container.read(dioProvider)..httpClientAdapter = fake;

      await expectLater(
        dio.get<Object?>('/transactions'),
        throwsA(isA<DioException>()),
      );

      expect(store.clearCount, 1);
      expect(container.read(sessionProvider).value, isNull);
    });
  });

  group('FakeApi helpers', () {
    test('records the Idempotency-Key of a mutating call', () async {
      final key = newIdempotencyKey();
      final fake = FakeApi()..on('PUT', '/budgets', body: {'category': 'food'});
      final dio = clientFor(fake);

      await dio.put<Object?>(
        '/budgets',
        data: {'category': 'food', 'month': '2026-09', 'limitPaise': 450000},
        options: Options(headers: {idempotencyKeyHeader: key}),
      );

      final request = fake.requestsFor('PUT', '/budgets').single;
      expect(request.idempotencyKey, key);
      expect(request.jsonBody['limitPaise'], 450000);
    });

    test('failOnce fails the first call and lets the retry through', () async {
      final fake = FakeApi()
        ..on('POST', '/transactions/undo', body: {'restoredIds': <String>[]})
        ..failOnce('POST', '/transactions/undo');
      final dio = clientFor(fake);

      await expectLater(
        dio.post<Object?>('/transactions/undo', data: {'undoToken': 'x'}),
        throwsA(isA<DioException>()),
      );
      final retry = await dio.post<Object?>(
        '/transactions/undo',
        data: {'undoToken': 'x'},
      );

      expect(retry.statusCode, 200);
      expect(fake.requests, hasLength(2));
    });

    test('respondAfter delays the response', () async {
      final fake = FakeApi()
        ..respondAfter('GET', '/summary', const Duration(milliseconds: 60),
            body: {'totalPaise': 0});
      final dio = clientFor(fake);

      final stopwatch = Stopwatch()..start();
      await dio.get<Object?>('/summary');
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(50));
    });

    test('records query parameters', () async {
      final fake = FakeApi()..on('GET', '/transactions', body: {'items': []});
      final dio = clientFor(fake);

      await dio.get<Object?>(
        '/transactions',
        queryParameters: {'month': '2026-09', 'limit': 50},
      );

      expect(fake.requests.single.query, {'month': '2026-09', 'limit': '50'});
    });

    test('an unregistered route fails loudly', () async {
      final dio = clientFor(FakeApi());

      await expectLater(
        dio.get<Object?>('/nope'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error.toString(),
            'error',
            contains('no route for GET /nope'),
          ),
        ),
      );
    });
  });

  group('idempotency keys', () {
    test('are version 4 UUIDs', () {
      final key = newIdempotencyKey();

      expect(
        key,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('are unique', () {
      final keys = List.generate(500, (_) => newIdempotencyKey()).toSet();
      expect(keys, hasLength(500));
    });

    test('a holder keeps one key across retries until it is reset', () {
      final holder = IdempotencyKeyHolder();

      expect(holder.hasKey, isFalse);
      final first = holder.key;
      expect(holder.hasKey, isTrue);
      expect(holder.key, first, reason: 'a retry must reuse the key');

      holder.reset();
      expect(holder.hasKey, isFalse);
      expect(holder.key, isNot(first), reason: 'a new action needs a new key');
    });
  });
}
