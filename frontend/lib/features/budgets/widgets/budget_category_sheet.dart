import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../../transactions/widgets/transaction_tile.dart' show categoryIcon;
import '../state/budgets_provider.dart';

/// Which category to budget for.
///
/// Every category is offered, not only the unbudgeted ones: picking one that
/// already has a limit is how a customer edits it, and hiding it would make
/// the list look wrong.
class BudgetCategorySheet extends ConsumerWidget {
  const BudgetCategorySheet({super.key, this.budgets = const []});

  /// What is already budgeted this month, so a category can say so.
  final List<BudgetView> budgets;

  /// Completes with the chosen category id, or null when dismissed.
  static Future<String?> show(
    BuildContext context, {
    List<BudgetView> budgets = const [],
  }) {
    return showModalBottomSheet<String>(
      context: context,
      // Over the navigation bar too: this is a decision, not part of the tab.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: MediaQuery.of(context).disableAnimations
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => BudgetCategorySheet(budgets: budgets),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Semantics(
              header: true,
              child: Text(
                'Budget for which category?',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
          Flexible(
            child: categories.when(
              loading: () => const SkeletonList(itemCount: 6),
              error: (error, _) => AsyncErrorView(
                error: asBankError(error),
                title: 'We could not load the categories',
                onRetry: () => ref.invalidate(categoriesProvider),
              ),
              data: (items) => items.isEmpty
                  ? EmptyView(
                      icon: Icons.category_outlined,
                      title: 'No categories to choose from',
                      message: 'Your bank has not sent any categories yet. '
                          'Try again in a moment.',
                      action: OutlinedButton.icon(
                        onPressed: () => ref.invalidate(categoriesProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    )
                  : _CategoryList(categories: items, budgets: budgets),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.categories, required this.budgets});

  final List<Category> categories;
  final List<BudgetView> budgets;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final budgeted = budgets.forCategory(category.id);

        return ListTile(
          leading: Icon(categoryIcon(category.id)),
          title: Text(category.name),
          subtitle: budgeted == null
              ? null
              : Text('${formatPaise(budgeted.limitPaise)} a month'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pop(category.id),
        );
      },
    );
  }
}
