import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          _BudgetAlertHost(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Keeps the budget-alert listener alive for the whole session.
///
/// It sits above the navigator, so it outlives every screen: an alert about
/// the food budget is no use only to a customer who happens to be looking at
/// the Budgets tab. A widget of its own, so that the listener changing — the
/// permission being answered, or the month rolling over — rebuilds nothing
/// but this one node.
class _BudgetAlertHost extends ConsumerWidget {
  const _BudgetAlertHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(budgetAlertsProvider);
    return child;
  }
}
