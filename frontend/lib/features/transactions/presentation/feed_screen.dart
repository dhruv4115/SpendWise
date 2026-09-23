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
import '../state/day_groups.dart';
import '../state/feed_provider.dart';
import '../state/month_provider.dart';
import '../widgets/day_header.dart';
import '../widgets/transaction_tile.dart';

/// The Spending tab: a month of transactions, newest first, under a sticky
/// header for each day.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthProvider);
    final isLatestMonth = month == ref.watch(latestMonthProvider);
    final feedKey = FeedKey(month: month);
    final feed = ref.watch(feedProvider(feedKey));

    // Only a list with rows in it stays up while it refreshes — that is what
    // pull-to-refresh draws over. An error or an empty month gives way to the
    // skeleton, so tapping Retry or Refresh visibly does something.
    final keepRowsWhileRefreshing =
        !feed.hasError && (feed.valueOrNull?.items.isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        title: Text(monthKeyLabel(month)),
        actions: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => ref.read(monthProvider.notifier).previous(),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            // Nothing can have happened after the current month.
            onPressed: isLatestMonth
                ? null
                : () => ref.read(monthProvider.notifier).next(),
          ),
        ],
      ),
      body: feed.when(
        skipLoadingOnRefresh: keepRowsWhileRefreshing,
        loading: () => const SkeletonList(
          itemCount: 8,
          sectionCount: 2,
          label: 'Loading transactions',
        ),
        error: (error, _) => AsyncErrorView(
          error: asBankError(error),
          title: 'We could not load your transactions',
          onRetry: () => ref.invalidate(feedProvider(feedKey)),
          onSignInAgain: () => ref.read(sessionProvider.notifier).signOut(),
        ),
        data: (state) => state.items.isEmpty
            ? EmptyView(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions in ${monthKeyLabel(month)}',
                message:
                    'Payments and refunds from this month will show up here.',
                action: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(feedProvider(feedKey).notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              )
            : _FeedList(feedKey: feedKey, state: state),
      ),
    );
  }
}

class _FeedList extends ConsumerWidget {
  const _FeedList({required this.feedKey, required this.state});

  final FeedKey feedKey;
  final FeedState state;

  /// How close to the end, in pixels, the next page is requested: about five
  /// rows ahead, so a steady scroll rarely reaches the footer.
  static const double loadMoreThreshold = 400;

  void _maybeLoadMore(WidgetRef ref, ScrollMetrics metrics) {
    if (metrics.extentAfter > loadMoreThreshold) return;
    // After a failure, wait for the footer's Retry rather than re-sending the
    // request on every scroll event.
    if (!state.hasMore || state.isLoadingMore || state.loadMoreError != null) {
      return;
    }
    ref.read(feedProvider(feedKey).notifier).loadMore();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final headerExtent = DayHeader.extentOf(context);

    final sections = <Widget>[];
    var rowsBefore = 0;
    for (final group in groupByDay(state.items)) {
      sections.add(
        _DaySection(
          key: ValueKey(group.day),
          group: group,
          label: dayHeaderLabel(group.day, now: now),
          headerExtent: headerExtent,
          semanticIndexOffset: rowsBefore,
        ),
      );
      rowsBefore += group.items.length;
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(feedProvider(feedKey).notifier).refresh(),
      // Dispatched after any layout that changes the list's size, so a first
      // page too short to scroll still pulls in the next one.
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            _maybeLoadMore(ref, notification.metrics);
          }
          return false;
        },
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) {
              _maybeLoadMore(ref, notification.metrics);
            }
            return false;
          },
          child: CustomScrollView(
            // Pull-to-refresh has to work on a list shorter than the screen.
            physics: const AlwaysScrollableScrollPhysics(),
            semanticChildCount: state.items.length,
            slivers: [
              ...sections,
              SliverToBoxAdapter(
                child: _FeedFooter(
                  state: state,
                  monthLabel: monthKeyLabel(feedKey.month),
                  onRetry: () =>
                      ref.read(feedProvider(feedKey).notifier).loadMore(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One day: a pinned header, then that day's rows.
class _DaySection extends StatelessWidget {
  const _DaySection({
    super.key,
    required this.group,
    required this.label,
    required this.headerExtent,
    required this.semanticIndexOffset,
  });

  final DayGroup group;
  final String label;
  final double headerExtent;

  /// Rows in earlier sections, so a screen reader counts "row 40 of 1,000"
  /// across the whole feed rather than restarting at every header.
  final int semanticIndexOffset;

  @override
  Widget build(BuildContext context) {
    final items = group.items;

    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: DayHeaderDelegate(
            label: label,
            totalPaise: group.totalPaise,
            extent: headerExtent,
          ),
        ),
        // Every row is the prototype's height, so the list places rows by
        // arithmetic instead of laying each one out, and knows its exact
        // length without building the rows off screen.
        SliverPrototypeExtentList(
          prototypeItem: TransactionTile.prototype,
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final txn = items[index];
              return RepaintBoundary(
                child: TransactionTile(
                  transaction: txn,
                  onTap: () => context.push(Routes.transactionDetail(txn.id)),
                ),
              );
            },
            childCount: items.length,
            // The RepaintBoundary above is the only one: the delegate would
            // otherwise add a second. Stateless rows have nothing to keep
            // alive.
            addRepaintBoundaries: false,
            addAutomaticKeepAlives: false,
            semanticIndexOffset: semanticIndexOffset,
          ),
        ),
      ],
    );
  }
}

/// Below the last row: fetching, failed with a Retry, or the end.
class _FeedFooter extends StatelessWidget {
  const _FeedFooter({
    required this.state,
    required this.monthLabel,
    required this.onRetry,
  });

  final FeedState state;
  final String monthLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final Widget child;
    if (state.isLoadingMore) {
      // A spinner is motion; under reduced motion the words stand alone.
      final animate = !MediaQuery.of(context).disableAnimations;
      child = Semantics(
        liveRegion: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (animate) ...[
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(child: Text('Loading more transactions…', style: muted)),
          ],
        ),
      );
    } else if (state.loadMoreError case final BankError error) {
      child = Column(
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              error.userMessage,
              style: muted,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    } else if (!state.hasMore) {
      child = Text(
        "That's everything for $monthLabel.",
        style: muted,
        textAlign: TextAlign.center,
      );
    } else {
      child = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Center(child: child),
    );
  }
}
