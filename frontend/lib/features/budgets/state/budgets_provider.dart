import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/budget_repository.dart';
import '../domain/budget.dart';

/// One month's budgets, keyed by `YYYY-MM`.
///
/// Each budget carries its category's spend, so a recategorisation
/// invalidates this for the months it touched.
final AutoDisposeFutureProviderFamily<List<Budget>, String> budgetsProvider =
    FutureProvider.autoDispose.family<List<Budget>, String>(
  (ref, month) => ref.watch(budgetRepositoryProvider).fetchBudgets(month),
);
