import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/offline_cache.dart';
import '../../../core/cache/stale_data.dart';
import '../../../core/errors/bank_error.dart';
import '../../transactions/state/feed_provider.dart';
import '../../transactions/state/month_provider.dart';
import '../data/summarise_async.dart';
import '../data/summary_repository.dart';
import '../domain/month_summary.dart';

/// The server's summary of one month, keyed by `YYYY-MM`.
///
/// One small request, so it is what the Overview paints first. A
/// recategorisation invalidates it for the months it touched.
///
/// Cache first, then the network: a month looked at in the last day is on
/// screen in the frame it is asked for, and the server's copy replaces it
/// when it lands. A month that cannot be fetched at all falls back to what
/// was saved, and says so through [staleDataProvider].
class SummaryNotifier
    extends AutoDisposeFamilyAsyncNotifier<MonthSummary, String> {
  /// Bumped on every rebuild and on dispose, so a background refresh that
  /// lands late knows the month it was for has moved on.
  int _generation = 0;

  /// Whether this month has been served once already. The cache is for
  /// opening a month, not for re-reading one: a pull-to-refresh, a Retry and
  /// the invalidation after a recategorisation all mean "ask the server",
  /// and answering them from the copy this provider saved a moment ago would
  /// make all three do nothing.
  bool _opened = false;

  @override
  Future<MonthSummary> build(String month) async {
    final coldStart = !_opened;
    _opened = true;
    ref.onDispose(() => _generation++);
    // The three most recent months stay resident, so stepping between them is
    // a rebuild rather than a round trip. Older ones go as soon as nothing is
    // looking at them, which is what keeps memory flat.
    if (ref.watch(residentMonthsProvider).contains(month)) ref.keepAlive();

    final repository = ref.watch(summaryRepositoryProvider);

    final saved = coldStart ? await repository.cachedSummary(month) : null;
    if (saved != null && saved.isFresh) {
      unawaited(_refreshInBackground(saved));
      return saved.value;
    }

    final result = await repository.refreshSummary(month);
    _report(result);
    return result.value;
  }

  /// The refresh behind a saved copy that is already on screen.
  ///
  /// Never turns into an error: the customer is looking at numbers that were
  /// right a few hours ago, and replacing them with a red screen because the
  /// lift lost signal would be a downgrade. A failure raises the banner
  /// instead.
  Future<void> _refreshInBackground(Cached<MonthSummary> saved) async {
    final generation = _generation;
    final hold = ref.keepAlive();
    try {
      final result =
          await ref.read(summaryRepositoryProvider).refreshSummary(arg);
      if (generation != _generation) return;
      _report(result);
      state = AsyncData(result.value);
    } on BankError {
      if (generation == _generation) _report(saved.asStale());
    } finally {
      hold.close();
    }
  }

  void _report(Cached<MonthSummary> result) {
    ref
        .read(staleDataProvider(arg).notifier)
        .report(summarySource, result.isStale ? result.savedAt : null);
  }

  /// Fetches again, keeping the current numbers on screen until the new ones
  /// land. Never throws — a failure is in [state] — so pull-to-refresh can
  /// await it.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } on BankError {
      // Already in state as an AsyncError; the screen renders it.
    }
  }
}

final AutoDisposeAsyncNotifierProviderFamily<SummaryNotifier, MonthSummary,
        String> summaryProvider =
    AsyncNotifierProvider.autoDispose
        .family<SummaryNotifier, MonthSummary, String>(SummaryNotifier.new);

/// [month] worked out on the device from the feed's own rows, or null until
/// that is possible.
///
/// Possible once the month's unfiltered feed has every page and the server
/// summary has said what last month came to (a feed only knows its own
/// month). From then on the Overview follows the rows the customer can see —
/// an optimistic recategorisation moves the donut on the same beat as the
/// list, with no round trip, and the two never disagree by a paisa.
///
/// It watches that feed, so opening the Overview also fetches the feed's
/// first page: the Spending tab shows the same month and opens on it
/// instantly. A month too big for one page stays on the server's numbers
/// until someone scrolls it to the end.
final AutoDisposeFutureProviderFamily<MonthSummary?, String>
    localSummaryProvider = FutureProvider.autoDispose
        .family<MonthSummary?, String>((ref, month) async {
  final rows = ref.watch(
    feedProvider(FeedKey(month: month)).select((feed) {
      final state = feed.valueOrNull;
      // The list itself, not a copy: a new page or a patched row replaces
      // it, which is exactly when the sums need doing again.
      return state == null || state.hasMore ? null : state.items;
    }),
  );
  final previousTotal = ref.watch(
    summaryProvider(month)
        .select((summary) => summary.valueOrNull?.prevTotalPaise),
  );
  if (rows == null || previousTotal == null) return null;

  return summariseAsync(rows, month, prevTotalPaise: previousTotal);
});

/// How many rows a background aggregation is folding right now, or null when
/// nothing is being folded.
///
/// Only months big enough to have gone to an isolate report anything: a
/// spinner for four milliseconds of work would be a flicker, not an
/// explanation. The count is the feed's, because that is exactly what
/// [summariseAsync] was handed.
final AutoDisposeProviderFamily<int?, String> crunchingProvider =
    Provider.autoDispose.family<int?, String>((ref, month) {
  final rows = ref.watch(
    feedProvider(FeedKey(month: month))
        .select((feed) => feed.valueOrNull?.items.length ?? 0),
  );
  if (rows <= isolateThresholdRows) return null;

  final folding = ref.watch(
    localSummaryProvider(month).select((summary) => summary.isLoading),
  );
  return folding ? rows : null;
});
