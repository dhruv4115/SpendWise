import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/app_lock.dart';
import '../features/alerts/state/budget_alert_listener.dart';
import 'router.dart';
import 'theme.dart';

/// The root widget: theme plus router, and nothing else.
///
/// There is no `home` and no navigation logic here. Which screen the app opens
/// on is decided by the router's redirect, from the session state alone.
class SpendWiseApp extends ConsumerWidget {
  const SpendWiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SpendWise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          _SessionServices(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Keeps the two session-long jobs alive: the budget-alert listener and the
/// app lock.
///
/// It sits above the navigator, so both outlive every screen. An alert about
/// the food budget is no use only to a customer who happens to be looking at
/// the Budgets tab, and a lock that only watched the lifecycle while one
/// screen was up would not be a lock at all. A widget of its own, so that
/// either of them changing — a permission answered, the month rolling over,
/// the app going away — rebuilds nothing but this one node.
class _SessionServices extends ConsumerWidget {
  const _SessionServices({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref
      ..watch(budgetAlertsProvider)
      ..watch(appLockProvider);
    return child;
  }
}
