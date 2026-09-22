import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ProviderContainer that disposes itself when the test ends.
///
/// Forgetting the teardown leaks listeners between tests and produces failures
/// that look like flakes, so this is the only way tests should build one.
ProviderContainer makeContainer({List<Override> overrides = const []}) {
  final container = ProviderContainer(overrides: overrides);
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
