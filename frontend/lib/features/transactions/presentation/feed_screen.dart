import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/errors/bank_error.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/stale_banner.dart';
import '../../auth/state/session_provider.dart';
import '../domain/transaction_filter.dart';
import '../state/day_groups.dart';
import '../state/feed_provider.dart';
import '../state/filter_provider.dart';
import '../state/month_provider.dart';
import '../widgets/active_filters_row.dart';
import '../widgets/day_header.dart';
import '../widgets/transaction_tile.dart';
import 'filters_sheet.dart';
import 'month_switcher.dart';

/// The Spending tab: a month of transactions, newest first, under a sticky
/// header for each day — narrowed by the app-wide filter.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key, this.category});

  /// From the address, `/transactions?category=food`: the Overview's donut
  /// opens the feed on the slice that was tapped.
  ///
  /// A seed, not the filter itself. It is read when the screen is first
  /// built — and again if the address brings a different one — and written
  /// into the app-wide filter; from then on the filter is the truth, and
  /// clearing the chip clears it whatever the address says. Null or empty
  /// seeds nothing.
  final String? category;

  /// How long typing has to pause before the search goes to the server.
  static const Duration searchDebounce = Duration(milliseconds: 300);

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

/// A feed that was on screen, and the key it was loaded for.
typedef _Shown = ({FeedKey key, FeedState state});

class _FeedScreenState extends ConsumerState<FeedScreen> {
  late final TextEditingController _search;
  Timer? _debounce;

  /// The address's category, until it has been written into the filter.
  String? _seed;

  /// The last settled feed this screen drew. A record of what the previous
  /// frame showed, not state that drives a rebuild: when the filter changes,
  /// these rows stay up, dimmed, until the new filter's first page lands.
  _Shown? _shown;

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;

  @override
  void initState() {
    super.initState();
    _seed = _nonEmpty(widget.category);
    // A seed replaces the whole filter, search included.
    _search = TextEditingController(
      text: _seed == null ? ref.read(filterStateNotifier).query : '',
    );
    if (_seed != null) _applySeedAfterFrame();
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final seed = _nonEmpty(widget.category);
    if (seed != null && seed != _nonEmpty(oldWidget.category)) {
      _seed = seed;
      _applySeedAfterFrame();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// A provider cannot change while the tree is building, so the seed is
  /// written after this frame. [build] uses it in the meantime, so the first
  /// request already carries the category — rather than an unfiltered one
  /// that is thrown away a frame later.
  void _applySeedAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final seed = _seed;
      if (!mounted || seed == null) return;
      _seed = null;
      // A slice means "this category, this month". Its rows should add up
      // to the slice, so nothing narrowed earlier carries over.
      ref
          .read(filterStateNotifier.notifier)
          .applyAll(TransactionFilter(category: seed));
    });
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(FeedScreen.searchDebounce, () => _commitSearch(text));
  }

  void _commitSearch(String text) {
    _debounce?.cancel();
    _debounce = null;
    ref.read(filterStateNotifier.notifier).setQuery(text);
  }

  void _clearSearch() {
    _search.clear();
    _commitSearch('');
  }

  Future<void> _openFilters() async {
    // Anything still in the debounce goes first: the sheet hands back a whole
    // filter, and it must not carry an out-of-date search.
    if (_debounce?.isActive ?? false) _commitSearch(_search.text);

    final result = await FiltersSheet.show(
      context,
      initial: ref.read(filterStateNotifier),
      month: ref.read(monthProvider),
    );
    // Dismissed: nothing changes.
    if (result == null || !mounted) return;
    ref.read(filterStateNotifier.notifier).applyAll(result);
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the search field in step with a search changed from elsewhere:
    // a chip's X, Clear filters, a seed.
    ref.listen<String>(
      filterStateNotifier.select((filter) => filter.query),
      (_, query) {
        if (query == _search.text.trim()) return;
        _debounce?.cancel();
        _search.text = query;
      },
    );

    final month = ref.watch(monthProvider);
    final stored = ref.watch(filterStateNotifier);
    final activeCount = ref.watch(activeFilterCountProvider);
    final seed = _seed;
    final filter = seed == null ? stored : TransactionFilter(category: seed);

    // A new filter is a new family key, so a new feed; the one it replaces
    // has no listener left and is disposed.
    final feedKey = FeedKey(month: month, filter: filter);
    final feed = ref.watch(feedProvider(feedKey));

    // Still on its first page with nothing to show, for a different filter
    // on the same month as what is on screen. A new month is not a
    // "filtering" — its old rows would be the wrong month's.
    final previous = _shown;
    final _Shown? outgoing = previous != null &&
            feed.isLoading &&
            !feed.hasValue &&
            !feed.hasError &&
            previous.key.month == month &&
            previous.key.filter != filter
        ? previous
        : null;

    if (feed.hasValue && !feed.isLoading && !feed.hasError) {
      _shown = (key: feedKey, state: feed.requireValue);
    } else if (feed.hasError && !feed.isLoading) {
      _shown = null;
    }

    // Folds the rows that are on screen into the new feed's loading state,
    // so `when` sees a refresh of them: loading, with a previous value.
    final view = outgoing == null
        ? feed
        : feed.copyWithPrevious(AsyncData<FeedState>(outgoing.state));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending'),
        bottom: _searchBar(context, activeCount),
      ),
      body: Column(
        children: [
          const MonthSwitcher(warmFeed: true),
          StaleDataBanner(
            month: month,
            onRetry: () => ref.read(feedProvider(feedKey).notifier).refresh(),
          ),
          ActiveFiltersRow(filter: filter),
          Expanded(
            child: _body(
              view,
              feedKey,
              previousKey: outgoing?.key,
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _searchBar(BuildContext context, int activeCount) {
    // Tall enough for one line of search text at the customer's text size,
    // so the app bar never has to squeeze it.
    final style = Theme.of(context).textTheme.bodyLarge;
    final line = MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 16) *
        (style?.height ?? 1.5);
    final height = math.max(56.0, line + 16);

    return PreferredSize(
      preferredSize: Size.fromHeight(height + 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: SearchBar(
          controller: _search,
          hintText: 'Search merchants',
          constraints: BoxConstraints.tightFor(height: height),
          elevation: const WidgetStatePropertyAll(0),
          textInputAction: TextInputAction.search,
          // Decorative: the hint names the field.
          leading: const Icon(Icons.search),
          trailing: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _search,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: _clearSearch,
                    ),
            ),
            _FilterButton(count: activeCount, onPressed: _openFilters),
          ],
          onChanged: _onSearchChanged,
          // The keyboard's search key does not wait for the debounce.
          onSubmitted: _commitSearch,
        ),
      ),
    );
  }

  /// [previousKey] is set while the rows of that key stand in for a new
  /// filter's first page.
  Widget _body(
    AsyncValue<FeedState> view,
    FeedKey feedKey, {
    FeedKey? previousKey,
  }) {
    final month = feedKey.month;
    final filter = feedKey.filter;

    // skipLoadingOnRefresh is off on purpose. Every load — a first page, a
    // Retry, a pull-to-refresh, a new filter — reaches `loading`, and it
    // decides what the customer looks at while they wait:
    //  - a new filter: the old rows, dimmed, under "Filtering…";
    //  - a list with rows refreshing: that list, which pull-to-refresh
    //    draws over;
    //  - anything else — an error or an empty month being retried — the
    //    skeleton, so Retry and Refresh visibly do something.
    return view.when(
      skipLoadingOnRefresh: false,
      loading: () {
        final rows = view.hasError ? null : view.valueOrNull;
        final hasRows = rows != null && rows.items.isNotEmpty;
        if (previousKey != null) {
          return _FilteringView(
            child: hasRows
                ? _FeedList(feedKey: previousKey, state: rows, live: false)
                : const SkeletonList(
                    itemCount: 8,
                    sectionCount: 2,
                    label: 'Filtering transactions',
                  ),
          );
        }
        if (hasRows) return _FeedList(feedKey: feedKey, state: rows);
        return const SkeletonList(
          itemCount: 8,
          sectionCount: 2,
          label: 'Loading transactions',
        );
      },
      error: (error, _) => AsyncErrorView(
        error: asBankError(error),
        title: 'We could not load your transactions',
        onRetry: () => ref.invalidate(feedProvider(feedKey)),
        onSignInAgain: () => ref.read(sessionProvider.notifier).signOut(),
      ),
      data: (state) {
        if (state.items.isNotEmpty) {
          return _FeedList(feedKey: feedKey, state: state);
        }
        if (filter.isActive) {
          return EmptyView(
            icon: Icons.filter_alt_off_outlined,
            title: 'No results for these filters',
            message: 'Nothing in ${monthKeyLabel(month)} matches. Remove a '
                'filter above, or clear them all.',
            action: FilledButton.tonalIcon(
              onPressed: () => ref.read(filterStateNotifier.notifier).clear(),
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Clear filters'),
            ),
          );
        }
        return EmptyView(
          icon: Icons.receipt_long_outlined,
          title: 'No transactions in ${monthKeyLabel(month)}',
          message: 'Payments and refunds from this month will show up here.',
          action: OutlinedButton.icon(
            onPressed: () => ref.read(feedProvider(feedKey).notifier).refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        );
      },
    );
  }
}

/// Opens the filter sheet. The badge counts the filters applied; the tooltip
/// says the same in words, so the number is never the only signal.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: count == 0 ? 'Filters' : 'Filters, $count applied',
      onPressed: onPressed,
      // The tooltip already says how many; the badge's digit would only be
      // read out a second time.
      icon: ExcludeSemantics(
        child: Badge.count(
          count: count,
          isLabelVisible: count > 0,
          child: const Icon(Icons.tune),
        ),
      ),
    );
  }
}

/// The explicit in-between state of a filter change: says "Filtering…" and
/// keeps what was there underneath, dimmed and out of reach — those rows
/// belong to a filter that no longer applies.
class _FilteringView extends StatelessWidget {
  const _FilteringView({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // A moving bar is motion; under reduced motion the words stand alone.
    final animate = !MediaQuery.of(context).disableAnimations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (animate) const LinearProgressIndicator(minHeight: 2),
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.filter_list, size: 18, color: muted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Filtering…',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: Opacity(opacity: 0.38, child: child),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedList extends ConsumerWidget {
  const _FeedList({
    required this.feedKey,
    required this.state,
    this.live = true,
  });

  final FeedKey feedKey;
  final FeedState state;

  /// False for the rows of a filter being replaced. Their feed is gone, so
  /// the list must never ask it for more: that would bring it back to life
  /// and send a request nobody will see.
  final bool live;

  /// How close to the end, in pixels, the next page is requested: about five
  /// rows ahead, so a steady scroll rarely reaches the footer.
  static const double loadMoreThreshold = 400;

  void _maybeLoadMore(WidgetRef ref, ScrollMetrics metrics) {
    if (!live || metrics.extentAfter > loadMoreThreshold) return;
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
                  filtered: feedKey.filter.isActive,
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
    required this.filtered,
    required this.onRetry,
  });

  final FeedState state;
  final String monthLabel;

  /// Whether the rows are only the ones matching a filter, which the last
  /// line then says rather than claiming the whole month.
  final bool filtered;
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
        filtered
            ? "That's every match in $monthLabel."
            : "That's everything for $monthLabel.",
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
