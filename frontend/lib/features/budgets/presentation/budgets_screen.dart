import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/errors/bank_error.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/state/session_provider.dart';
import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../../transactions/state/month_provider.dart';
import '../domain/budget.dart';
import '../state/budgets_provider.dart';
import '../widgets/budget_card.dart';
import '../widgets/budget_category_sheet.dart';

/// The Budgets tab: one card per category with a limit, showing how much of
/// this month's limit is gone and whether that is a problem yet.
///
/// A month the customer has not budgeted is not blank — last month's limits
/// carry over, marked as such, until the first edit makes them this month's.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  /// Opens one budget and, if it was saved, says so.
  ///
  /// The edit screen pops the budget it saved, so the confirmation belongs
  /// here: the customer reads it on the list they have just come back to.
  static Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String category,
  ) async {
    final saved = await context.push<Budget>(Routes.budgetDetail(category));
    if (saved == null || !context.mounted) return;

    final name =
        (ref.read(categoriesProvider).valueOrNull ?? const <Category>[])
            .nameOf(saved.category);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$name budget set to ${formatPaise(saved.limitPaise)} '
            'for ${monthKeyLabel(saved.month)}.',
          ),
        ),
      );
  }

  /// Picks a category first, then opens its budget.
  static Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<BudgetView> budgets,
  ) async {
    final category = await BudgetCategorySheet.show(context, budgets: budgets);
    if (category == null || !context.mounted) return;
    await _open(context, ref, category);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthProvider);
    final isLatestMonth = month == ref.watch(latestMonthProvider);
    final budgets = ref.watch(budgetsProvider(month));
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final monthLabel = monthKeyLabel(month);
    final rows = budgets.valueOrNull ?? const <BudgetView>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(monthLabel),
        actions: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => ref.read(monthProvider.notifier).previous(),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: isLatestMonth
                ? null
                : () => ref.read(monthProvider.notifier).next(),
          ),
          IconButton(
            tooltip: 'Add a budget',
            icon: const Icon(Icons.add),
            onPressed: () => _add(context, ref, rows),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(budgetsProvider(month).notifier).refresh(),
        child: budgets.when(
          loading: () => const _BudgetsSkeleton(),
          error: (error, _) => AsyncErrorView(
            error: asBankError(error),
            title: 'We could not load your budgets',
            onRetry: () => ref.read(budgetsProvider(month).notifier).refresh(),
            onSignInAgain: () => ref.read(sessionProvider.notifier).signOut(),
          ),
          data: (items) => items.isEmpty
              ? EmptyView(
                  icon: Icons.savings_outlined,
                  title: 'No budgets for $monthLabel',
                  message: 'Set a limit for a category and this screen will '
                      'show how much of it is left — and carry the limit on '
                      'to next month.',
                  action: FilledButton.icon(
                    onPressed: () => _add(context, ref, items),
                    icon: const Icon(Icons.add),
                    label: const Text('Set your first budget'),
                  ),
                )
              : ListView.separated(
                  // Pull-to-refresh works however short the list is.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final budget = items[index];
                    return BudgetCard(
                      budget: budget,
                      categoryName: categories.nameOf(budget.category),
                      onTap: () => _open(context, ref, budget.category),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// The shape of the list to come: three cards, each an icon, a bar and a
/// line of figures.
class _BudgetsSkeleton extends StatelessWidget {
  const _BudgetsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading budgets',
      liveRegion: true,
      container: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (var card = 0; card < 3; card++) ...[
            if (card > 0) const SizedBox(height: 12),
            const Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Skeleton(width: 40, height: 40, borderRadius: 20),
                        SizedBox(width: 12),
                        Expanded(child: Skeleton(width: 140, height: 16)),
                      ],
                    ),
                    SizedBox(height: 14),
                    Skeleton(height: 10, borderRadius: 5),
                    SizedBox(height: 12),
                    Skeleton(width: 180, height: 14),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
