import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/errors/bank_error.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/state/session_provider.dart';
import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../../transactions/state/month_provider.dart';
import '../domain/merchant_insight.dart';
import '../state/merchants_provider.dart';
import '../widgets/merchant_tile.dart';

/// `/merchants`: who the month's money went to, and how often.
class MerchantsScreen extends ConsumerWidget {
  const MerchantsScreen({super.key});

  /// What the menu offers for each order.
  static String menuLabel(MerchantSort sort) => switch (sort) {
        MerchantSort.total => 'Total spent',
        MerchantSort.visits => 'Number of visits',
        MerchantSort.average => 'Average spend',
      };

  /// What the list says it is doing, above the first row. The order is
  /// spelled out rather than left to the rows to imply.
  static String sortSummary(MerchantSort sort) => switch (sort) {
        MerchantSort.total => 'Most spent first',
        MerchantSort.visits => 'Most visits first',
        MerchantSort.average => 'Highest average first',
      };

  static Future<void> _refresh(WidgetRef ref, String month) async {
    ref.invalidate(merchantsProvider(month));
    try {
      await ref.read(merchantsProvider(month).future);
    } on BankError {
      // Already in state as an AsyncError; the screen renders it.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthProvider);
    final isLatestMonth = month == ref.watch(latestMonthProvider);
    final sort = ref.watch(merchantSortProvider);
    final merchants = ref.watch(sortedMerchantsProvider(month));
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final monthLabel = monthKeyLabel(month);

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
          _SortButton(
            sort: sort,
            onSelected: (choice) =>
                ref.read(merchantSortProvider.notifier).set(choice),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref, month),
        child: merchants.when(
          loading: () => const SkeletonList(
            itemCount: 6,
            label: 'Loading merchants',
            padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
          ),
          error: (error, _) => AsyncErrorView(
            error: asBankError(error),
            title: 'We could not load your merchants',
            onRetry: () => _refresh(ref, month),
            onSignInAgain: () => ref.read(sessionProvider.notifier).signOut(),
          ),
          data: (items) => items.isEmpty
              ? EmptyView(
                  icon: Icons.storefront_outlined,
                  title: 'Nothing spent in $monthLabel',
                  message: 'Once there are payments in this month, the shops '
                      'and services behind them are listed here, biggest '
                      'first.',
                )
              : _MerchantList(
                  merchants: items,
                  categories: categories,
                  sort: sort,
                ),
        ),
      ),
    );
  }
}

/// The order control: a menu rather than a row of segments, so three labelled
/// choices still fit on a narrow screen at a 2.0 text scale.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onSelected});

  final MerchantSort sort;
  final ValueChanged<MerchantSort> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MerchantSort>(
      // The button is an icon; the tooltip and the semantics label say what
      // it does, and the current order is written above the list.
      tooltip: 'Sort merchants',
      icon: const Icon(Icons.sort),
      initialValue: sort,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in MerchantSort.values)
          CheckedPopupMenuItem<MerchantSort>(
            value: option,
            checked: option == sort,
            child: Text(MerchantsScreen.menuLabel(option)),
          ),
      ],
    );
  }
}

class _MerchantList extends StatelessWidget {
  const _MerchantList({
    required this.merchants,
    required this.categories,
    required this.sort,
  });

  final List<MerchantInsight> merchants;
  final List<Category> categories;
  final MerchantSort sort;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Pull-to-refresh works however short the list is.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: merchants.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ListHeader(count: merchants.length, sort: sort);
        }
        final insight = merchants[index - 1];
        return MerchantTile(
          insight: insight,
          categoryName: categories.nameOf(insight.topCategory),
          onTap: () => context.push(Routes.merchantDetail(insight.merchantKey)),
        );
      },
    );
  }
}

/// How many merchants there are, and what order they are in.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.count, required this.sort});

  final int count;
  final MerchantSort sort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = '${count == 1 ? '1 merchant' : '$count merchants'} · '
        '${MerchantsScreen.sortSummary(sort)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Semantics(
        liveRegion: true,
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
