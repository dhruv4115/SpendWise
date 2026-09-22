import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/app/app.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';

import 'container.dart';
import 'fake_api.dart';
import 'fake_session_store.dart';

/// Wraps a widget in the same scope and theme the real app gives it, so a
/// widget test sees the production colours, text styles and risk palette.
///
/// ```dart
/// await tester.pumpWidget(testApp(
///   const BudgetCard(),
///   overrides: [dioProvider.overrideWithValue(dio)],
/// ));
/// ```
Widget testApp(
  Widget child, {
  List<Override> overrides = const [],
  ThemeMode themeMode = ThemeMode.light,
  NavigatorObserver? navigatorObserver,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      navigatorObservers: [
        if (navigatorObserver != null) navigatorObserver,
      ],
      home: child,
    ),
  );
}

/// [testApp] with a Scaffold around the child, for widgets that expect one
/// (anything using SnackBars, or Material ink).
Widget testScaffold(
  Widget child, {
  List<Override> overrides = const [],
  ThemeMode themeMode = ThemeMode.light,
}) {
  return testApp(
    Scaffold(body: child),
    overrides: overrides,
    themeMode: themeMode,
  );
}

/// The real app — real router, real guard, real repositories — wired to a
/// fake transport and a fake keystore.
///
/// Returns the container as well as the widget so a test can ask the router
/// where it ended up, and the store what it holds.
///
/// ```dart
/// final harness = routedApp(fake, store: FakeSessionStore());
/// await tester.pumpWidget(harness.app);
/// expect(harness.location, Routes.loginPath);
/// ```
TestHarness routedApp(
  FakeApi api, {
  FakeSessionStore? store,
  String initialLocation = Routes.splashPath,
  List<Override> overrides = const [],
}) {
  final sessionStore = store ?? FakeSessionStore();
  final container = makeContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(sessionStore),
      httpClientAdapterProvider.overrideWithValue(api),
      initialLocationProvider.overrideWithValue(initialLocation),
      ...overrides,
    ],
  );

  return TestHarness(container: container, store: sessionStore);
}

/// A container, the app it renders, and the handful of questions a routing
/// test needs to ask afterwards.
class TestHarness {
  TestHarness({required this.container, required this.store});

  final ProviderContainer container;
  final FakeSessionStore store;

  /// Shares the test's container rather than making its own, so the test and
  /// the widgets under it see the same providers.
  Widget get app => UncontrolledProviderScope(
        container: container,
        child: const SpendWiseApp(),
      );

  /// Where the router currently is, path and query.
  String get location => container.read(routerProvider).state.uri.toString();
}
