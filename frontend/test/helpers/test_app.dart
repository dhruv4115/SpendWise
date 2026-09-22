import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/app/theme.dart';

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
