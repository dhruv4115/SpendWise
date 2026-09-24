import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/cache/offline_cache.dart';
import 'package:spendwise/core/errors/bank_error.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/auth/data/auth_repository.dart';
import 'package:spendwise/features/auth/domain/session.dart';
import 'package:spendwise/features/auth/state/session_provider.dart';

import '../helpers/container.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_cache.dart';
import '../helpers/fake_session_store.dart';

void main() {
  group('SessionNotifier.restore', () {
    test('starts unknown, so the guard does not bounce a returning customer',
        () {
      final container = makeContainer(
        overrides: [
          sessionStoreProvider
              .overrideWithValue(FakeSessionStore(session: testSession)),
          httpClientAdapterProvider.overrideWithValue(FakeApi()),
        ],
      );

      // Read on the same turn the container is built: the keystore has not
      // answered yet, and "unknown" must not read as "signed out".
      expect(container.read(sessionProvider), const SessionUnknown());
      expect(container.read(isSignedInProvider), isFalse);
    });

    test('signs in from a stored session', () async {
      final store = FakeSessionStore(session: testSession);
      final container = makeContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          httpClientAdapterProvider.overrideWithValue(FakeApi()),
        ],
      );
      readAndKeepAlive(container, sessionProvider);

      await container.read(sessionProvider.notifier).restore();

      expect(container.read(sessionProvider), SessionSignedIn(testSession));
      expect(container.read(sessionProvider).session, testSession);
      expect(container.read(isSignedInProvider), isTrue);
    });

    test('signs out when the keystore is empty', () async {
      final container = makeContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(FakeSessionStore()),
          httpClientAdapterProvider.overrideWithValue(FakeApi()),
        ],
      );
      readAndKeepAlive(container, sessionProvider);

      await container.read(sessionProvider.notifier).restore();

      expect(container.read(sessionProvider), const SessionSignedOut());
      expect(container.read(isSignedInProvider), isFalse);
    });

    test('restores on boot without anyone asking it to', () async {
      final container = makeContainer(
        overrides: [
          sessionStoreProvider
              .overrideWithValue(FakeSessionStore(session: testSession)),
          httpClientAdapterProvider.overrideWithValue(FakeApi()),
        ],
      );
      readAndKeepAlive(container, sessionProvider);

      // One turn of the event loop is all the fake keystore needs.
      await Future<void>.delayed(Duration.zero);

      expect(container.read(sessionProvider), SessionSignedIn(testSession));
    });
  });

  group('SessionNotifier transitions', () {
    test('signOut clears the keystore as well as the state', () async {
      final store = FakeSessionStore(session: testSession);
      final container = makeContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          httpClientAdapterProvider.overrideWithValue(FakeApi()),
        ],
      );
      readAndKeepAlive(container, sessionProvider);
      await container.read(sessionProvider.notifier).restore();

      await container.read(sessionProvider.notifier).signOut();

      expect(container.read(sessionProvider), const SessionSignedOut());
      expect(store.clearCount, 1);
      expect(store.stored, isNull);
    });

    test('signing out takes the saved months with it', () async {
      final saved = FakeOfflineCache()
        ..seed(summaryCacheKey('2026-09'), const {'totalPaise': 1})
        ..seed(transactionsCacheKey('2026-09'), const {'items': <Object>[]});
      final container = makeContainer(
        cache: saved,
        overrides: [
          sessionStoreProvider.overrideWithValue(
            FakeSessionStore(session: testSession),
          ),
          httpClientAdapterProvider.overrideWithValue(FakeApi()),
        ],
      );
      readAndKeepAlive(container, sessionProvider);
      await container.read(sessionProvider.notifier).restore();

      await container.read(sessionProvider.notifier).signOut();

      // One customer's statements must not be handed to the next person to
      // sign in on this phone.
      expect(await saved.months(), isEmpty);
      expect(await saved.read(summaryCacheKey('2026-09')), isNull);
      expect(await saved.read(transactionsCacheKey('2026-09')), isNull);
    });

    test('lock keeps the session and unlock gives it back', () async {
      final container = makeContainer(
        overrides: [
          sessionStoreProvider
              .overrideWithValue(FakeSessionStore(session: testSession)),
          httpClientAdapterProvider.overrideWithValue(FakeApi()),
        ],
      );
      readAndKeepAlive(container, sessionProvider);
      await container.read(sessionProvider.notifier).restore();

      container.read(sessionProvider.notifier).lock();
      expect(container.read(sessionProvider), SessionLocked(testSession));
      // A locked app holds a valid token but must not count as signed in.
      expect(container.read(isSignedInProvider), isFalse);

      container.read(sessionProvider.notifier).unlock();
      expect(container.read(sessionProvider), SessionSignedIn(testSession));
    });
  });

  group('a 401 from the interceptor', () {
    test('drives the session to signed out and empties the keystore', () async {
      final store = FakeSessionStore(session: testSession);
      final api = FakeApi()
        ..respondError(
          'GET',
          '/transactions',
          status: 401,
          code: 'AUTH_TOKEN_INVALID',
          message: 'Your session has ended.',
        );
      final container = makeContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          httpClientAdapterProvider.overrideWithValue(api),
        ],
      );
      readAndKeepAlive(container, sessionProvider);
      await container.read(sessionProvider.notifier).restore();
      expect(container.read(sessionProvider), SessionSignedIn(testSession));

      await expectLater(
        container.read(dioProvider).get<Object?>('/transactions'),
        throwsA(isA<DioException>()),
      );

      expect(container.read(sessionProvider), const SessionSignedOut());
      expect(store.clearCount, 1);
      expect(api.requests, hasLength(1), reason: 'must not retry');
    });

    test('leaves a failed sign-in alone: that is a wrong password', () async {
      final store = FakeSessionStore();
      final api = FakeApi()
        ..respondError(
          'POST',
          '/auth/login',
          status: 401,
          code: 'AUTH_INVALID_CREDENTIALS',
          message: 'That email or password is not right.',
        );
      final container = makeContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          httpClientAdapterProvider.overrideWithValue(api),
        ],
      );
      readAndKeepAlive(container, sessionProvider);
      await container.read(sessionProvider.notifier).restore();

      await expectLater(
        container.read(authRepositoryProvider).login(
              email: 'asha@example.com',
              password: 'wrong-password',
              idempotencyKey: 'key-1',
            ),
        throwsA(isA<UnauthorisedError>()),
      );

      // The customer was already signed out; nothing was cleared on top of it.
      expect(store.clearCount, 0);
    });
  });

  group('AuthRepository', () {
    ({FakeApi api, FakeSessionStore store, AuthRepository repository}) build(
      FakeApi api,
    ) {
      final store = FakeSessionStore();
      final container = makeContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          httpClientAdapterProvider.overrideWithValue(api),
        ],
      );
      return (
        api: api,
        store: store,
        repository: container.read(authRepositoryProvider),
      );
    }

    test('returns the session and remembers it', () async {
      final harness = build(
        FakeApi()..on('POST', '/auth/login', body: testLoginResponse),
      );

      final session = await harness.repository.login(
        email: 'asha@example.com',
        password: 'password123',
        idempotencyKey: 'key-1',
      );

      expect(session, testSession);
      expect(session.name, 'Asha Rao');
      expect(harness.store.stored, testSession);
    });

    test('sends the Idempotency-Key it was given', () async {
      final harness = build(
        FakeApi()..on('POST', '/auth/login', body: testLoginResponse),
      );

      await harness.repository.login(
        email: 'asha@example.com',
        password: 'password123',
        idempotencyKey: 'key-abc',
      );

      final request = harness.api.requestsFor('POST', '/auth/login').single;
      expect(request.idempotencyKey, 'key-abc');
      expect(request.jsonBody['email'], 'asha@example.com');
    });

    test('throws BankError, never DioException', () async {
      final harness = build(
        FakeApi()
          ..respondError(
            'POST',
            '/auth/login',
            status: 401,
            code: 'AUTH_INVALID_CREDENTIALS',
            message: 'That email or password is not right.',
          ),
      );

      await expectLater(
        harness.repository.login(
          email: 'asha@example.com',
          password: 'nope12345',
          idempotencyKey: 'key-1',
        ),
        throwsA(
          isA<UnauthorisedError>()
              .having((e) => e.userMessage, 'userMessage',
                  'That email or password is not right.')
              .having((e) => e.traceId, 'traceId', isNotNull),
        ),
      );
      expect(harness.store.stored, isNull);
    });

    test('a 200 with an unusable body is still a BankError', () async {
      final harness = build(
        FakeApi()..on('POST', '/auth/login', body: {'token': 'tok_1'}),
      );

      await expectLater(
        harness.repository.login(
          email: 'asha@example.com',
          password: 'password123',
          idempotencyKey: 'key-1',
        ),
        throwsA(
          isA<BankError>().having(
            (e) => e.userMessage,
            'userMessage',
            'Something went wrong. Please try again.',
          ),
        ),
      );
    });

    test('logout clears the keystore', () async {
      final harness = build(
        FakeApi()..on('POST', '/auth/login', body: testLoginResponse),
      );
      await harness.repository.login(
        email: 'asha@example.com',
        password: 'password123',
        idempotencyKey: 'key-1',
      );

      await harness.repository.logout();

      expect(harness.store.stored, isNull);
      expect(harness.store.clearCount, 1);
    });
  });

  group('Session', () {
    test('parses the sign-in envelope', () {
      final session = Session.fromJson(Map<String, Object?>.from({
        'token': 'tok_1',
        'user': {'id': 'usr_1', 'name': 'Asha Rao', 'email': 'a@example.com'},
      }));

      expect(session.token, 'tok_1');
      expect(session.userId, 'usr_1');
      expect(session.name, 'Asha Rao');
      expect(session.email, 'a@example.com');
    });

    test('rejects a response with no token', () {
      expect(
        () => Session.fromJson(const {'user': <String, Object?>{}}),
        throwsA(isA<FormatException>()),
      );
    });

    test('never prints the token, the id or the email', () {
      expect(testSession.toString(), isNot(contains(testSession.token)));
      expect(testSession.toString(), isNot(contains(testSession.userId)));
      expect(testSession.toString(), isNot(contains(testSession.email)));
      expect(testSession.toString(), contains('Asha Rao'));
    });

    test('is a value', () {
      expect(testSession, testSession.copyWith());
      expect(testSession.hashCode, testSession.copyWith().hashCode);
      expect(testSession, isNot(testSession.copyWith(token: 'tok_other')));
    });
  });
}
