import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/errors/bank_error.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/auth/state/session_provider.dart';
import 'package:spendwise/features/categories/state/categories_provider.dart';

import '../helpers/categories.dart';
import '../helpers/container.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';

const String _path = '/categories';

ProviderContainer _container(FakeApi api) {
  return makeContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(
        FakeSessionStore(session: testSession),
      ),
      httpClientAdapterProvider.overrideWithValue(api),
    ],
  );
}

/// Lets the session finish reading the keystore, as the splash screen would.
Future<void> _signedIn(ProviderContainer container) async {
  container.read(sessionProvider);
  await pumpEventQueue();
  expect(container.read(sessionProvider), isA<SessionSignedIn>());
}

void main() {
  test('fetches once and keeps the list for the session', () async {
    final api = FakeApi()..on('GET', _path, body: categoriesWire());
    final container = _container(api);
    await _signedIn(container);

    final first = await container.read(categoriesProvider.future);
    // Nothing is listening in between: an auto-disposing provider would
    // have gone, and fetched again.
    await pumpEventQueue();
    final second = await container.read(categoriesProvider.future);

    expect(first, hasLength(10));
    expect(identical(first, second), isTrue);
    expect(api.requestsFor('GET', _path), hasLength(1));
    expect(first.nameOf('food'), 'Food & Dining');
    expect(first.nameOf('crypto'), 'Crypto',
        reason: 'an unknown id still gets a readable name');
  });

  test('a failure is not cached past a retry', () async {
    final api = FakeApi()..on('GET', _path, body: categoriesWire());
    api.failOnce('GET', _path);
    final container = _container(api);
    await _signedIn(container);

    await expectLater(
      container.read(categoriesProvider.future),
      throwsA(isA<ServerError>()),
    );
    container.invalidate(categoriesProvider);

    expect(await container.read(categoriesProvider.future), hasLength(10));
  });

  test(
      'signing out drops the list without asking; signing in fetches it '
      'afresh', () async {
    final api = FakeApi()..on('GET', _path, body: categoriesWire());
    final container = _container(api);
    await _signedIn(container);
    readAndKeepAlive(container, categoriesProvider);
    await container.read(categoriesProvider.future);

    await container.read(sessionProvider.notifier).signOut();
    await pumpEventQueue();

    expect(container.read(categoriesProvider).error, isA<UnauthorisedError>());
    expect(api.requestsFor('GET', _path), hasLength(1),
        reason: 'no token, so no request');

    container.read(sessionProvider.notifier).signIn(testSession);
    await container.read(categoriesProvider.future);

    expect(api.requestsFor('GET', _path), hasLength(2));
  });
}
