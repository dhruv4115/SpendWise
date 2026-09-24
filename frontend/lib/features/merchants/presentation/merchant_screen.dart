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
import '../../transactions/domain/transaction.dart';
import '../../transactions/presentation/recategorise_flow.dart';
import '../../transactions/state/month_provider.dart';
import '../../transactions/state/recategorise_controller.dart';
import '../../transactions/widgets/category_sheet.dart';
import '../../transactions/widgets/transaction_tile.dart';
import '../domain/merchant_insight.dart';
import '../state/merchants_provider.dart';

/// `/merchants/:id`, where the id is a merchant key: everything this merchant
/// took this month, what it is all filed as, and the one action that changes
/// that in a single step.
class MerchantScreen extends ConsumerWidget {
  const MerchantScreen({super.key, required this.merchantKey});

  /// From the route's path parameter.
  final String merchantKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An empty key would ask for `/merchants/`, which is the list.
    if (merchantKey.isEmpty) {
      return const _Frame(title: 'Merchant', child: _NotFound());
    }

    final month = ref.watch(monthProvider);
    final merchants = ref.watch(merchantsProvider(month));
    final insight = merchants.valueOrNull?.byKey(merchantKey);

    return _Frame(
      title: insight?.merchantName ?? 'Merchant',
      child: merchants.when(
        loading: () => const SkeletonList(
          itemCount: 5,
          label: 'Loading merchant',
          padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
        ),
        error: (error, _) => AsyncErrorView(
          error: asBankError(error),
          title: 'We could not load this merchant',
          onRetry: () => ref.invalidate(merchantsProvider(month)),
          onSignInAgain: () => ref.read(sessionProvider.notifier).signOut(),
        ),
        data: (_) => insight == null
            ? _NotFound(month: month)
            : _MerchantMonth(insight: insight, month: month),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

/// No such merchant — in this month, or at all.
class _NotFound extends StatelessWidget {
  const _NotFound({this.month});

  /// `YYYY-MM`, when the screen knows which month came up empty.
  final String? month;

  @override
  Widget build(BuildContext context) {
    final where = month == null ? 'this month' : monthKeyLabel(month!);

    return EmptyView(
      icon: Icons.storefront_outlined,
      title: 'Nothing from this merchant in $where',
      message: 'They may have a different name on your statement, or there '
          'may simply have been no payments to them in this month.',
      action: FilledButton(
        onPressed: () => context.go(Routes.merchantsPath),
        child: const Text('Back to Merchants'),
      ),
    );
  }
}

/// One merchant's month: the roll-up, the rule, the action and the rows.
class _MerchantMonth extends ConsumerWidget {
  const _MerchantMonth({required this.insight, required this.month});

  final MerchantInsight insight;

  /// `YYYY-MM`.
  final String month;

  MerchantMonthKey get _key => MerchantMonthKey(
        month: month,
        merchantKey: insight.merchantKey,
        merchantName: insight.merchantName,
      );

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(merchantsProvider(month))
      ..invalidate(merchantRowsProvider(_key));
    try {
      await ref.read(merchantRowsProvider(_key).future);
    } on BankError {
      // Already in state as an AsyncError; the screen renders it.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(merchantRowsProvider(_key));
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: CustomScrollView(
        // Pull-to-refresh works however short the screen's contents are.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _Summary(
              insight: insight,
              month: month,
              categoryName: categories.nameOf(insight.topCategory),
            ),
          ),
          ...rows.when(
            loading: () => const [
              SliverToBoxAdapter(
                child: SkeletonList(
                  itemCount: 4,
                  label: 'Loading payments',
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
                ),
              ),
            ],
            error: (error, _) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: AsyncErrorView(
                  error: asBankError(error),
                  title: 'We could not load these payments',
                  onRetry: () => ref.invalidate(merchantRowsProvider(_key)),
                  onSignInAgain: () =>
                      ref.read(sessionProvider.notifier).signOut(),
                ),
              ),
            ],
            data: (loaded) => loaded.isEmpty
                ? const [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyView(
                        icon: Icons.receipt_long_outlined,
                        title: 'No payments to show',
                        message: 'This merchant is in the month\'s summary, '
                            'but none of their payments came back. Pull down '
                            'to try again.',
                      ),
                    ),
                  ]
                : [
                    SliverToBoxAdapter(
                      child: _Actions(
                        merchantName: insight.merchantName,
                        // The newest payment stands for the merchant: the
                        // change is addressed to one row and applied to all
                        // of them by the server.
                        representative: loaded.transactions.first,
                        rule: loaded.rule == null
                            ? null
                            : categories.nameOf(loaded.rule!.category),
                      ),
                    ),
                    SliverList.separated(
                      itemCount: loaded.transactions.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 68),
                      itemBuilder: (context, index) {
                        final transaction = loaded.transactions[index];
                        return TransactionTile(
                          transaction: transaction,
                          onTap: () => context
                              .push(Routes.transactionDetail(transaction.id)),
                        );
                      },
                    ),
                    SliverToBoxAdapter(
                      child: _ListFooter(
                        count: loaded.transactions.length,
                        isComplete: loaded.isComplete,
                      ),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

/// The three figures the list screen shows, in full.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.insight,
    required this.month,
    required this.categoryName,
  });

  final MerchantInsight insight;
  final String month;
  final String categoryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visits =
        insight.visits == 1 ? '1 payment' : '${insight.visits} payments';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                monthKeyLabel(month),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              // Stacked rather than in a row of three: at a 2.0 text scale
              // three columns of rupees do not fit a phone.
              _Figure(
                  label: 'Total spent', value: formatPaise(insight.totalPaise)),
              const SizedBox(height: 10),
              _Figure(label: 'Payments', value: visits),
              const SizedBox(height: 10),
              _Figure(
                label: 'Average payment',
                value: formatPaise(insight.avgPaise),
              ),
              const SizedBox(height: 10),
              _Figure(label: 'Mostly filed as', value: categoryName),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label and its value, read as one phrase.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The merchant's rule, when it has one, and the button that sets it.
class _Actions extends ConsumerWidget {
  const _Actions({
    required this.merchantName,
    required this.representative,
    required this.rule,
  });

  final String merchantName;
  final Transaction representative;

  /// The name of the category every payment is in, or null when they are
  /// spread across several.
  final String? rule;

  Future<void> _changeAll(BuildContext context, WidgetRef ref) async {
    ref
        .read(recategoriseControllerProvider(representative.id).notifier)
        .beginEdit();

    final choice = await CategorySheet.show(
      context,
      representative,
      lockToMerchant: true,
    );
    if (choice == null || !context.mounted) return;

    await RecategoriseFlow.capture(context, ref, representative).commit(choice);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Watching also keeps the controller alive for as long as the screen is.
    final busy = ref.watch(
      recategoriseControllerProvider(representative.id)
          .select((state) => state.isLoading),
    );
    final category = rule;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (category != null)
            _RuleBanner(merchantName: merchantName, categoryName: category)
          else
            Text(
              'These payments are in more than one category.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => _changeAll(context, ref),
            icon: const Icon(Icons.edit_outlined),
            label: Text(
              busy ? 'Saving…' : 'Change category for all $merchantName',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Everything from this merchant is filed here."
class _RuleBanner extends StatelessWidget {
  const _RuleBanner({required this.merchantName, required this.categoryName});

  final String merchantName;
  final String categoryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Decorative: the sentence beside it says the same thing.
            ExcludeSemantics(
              child: Icon(
                Icons.rule_folder_outlined,
                size: MediaQuery.textScalerOf(context).scale(20),
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Every $merchantName payment this month is in $categoryName.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How many rows are on screen, and whether that is all of them.
class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.count, required this.isComplete});

  final int count;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = isComplete
        ? (count == 1 ? '1 payment this month' : '$count payments this month')
        : 'The first $count payments of this month';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
