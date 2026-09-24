import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/cache/offline_cache.dart';

import 'fake_cache.dart';

/// A ProviderContainer that disposes itself when the test ends.
///
/// Forgetting the teardown leaks listeners between tests and produces failures
/// that look like flakes, so this is the only way tests should build one.
///
/// The offline cache is in-memory and starts empty, so a test that says
/// nothing about it gets a cold cache and goes to the network — and no test
/// ever depends on a file another test left on disk. A test that wants a warm
/// one passes its own seeded [FakeOfflineCache] as [cache].
ProviderContainer makeContainer({
  List<Override> overrides = const [],
  OfflineCache? cache,
}) {
  final container = ProviderContainer(
    overrides: [
      offlineCacheProvider.overrideWithValue(cache ?? FakeOfflineCache()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Keeps a provider alive for the duration of a test.
///
/// Without a listener, a container disposes a provider as soon as its last
/// read finishes, so state set by one call is gone by the next.
T readAndKeepAlive<T>(
    ProviderContainer container, ProviderListenable<T> provider) {
  container.listen<T>(provider, (_, __) {}, fireImmediately: true);
  return container.read(provider);
}
