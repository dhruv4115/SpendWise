import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../transactions/state/feed_provider.dart';
import '../data/summarise_async.dart';
import '../data/summary_repository.dart';
import '../domain/month_summary.dart';

/// The server's summary of one month, keyed by `YYYY-MM`.
///
/// One small request, so it is what the Overview paints first. A
/// recategorisation invalidates it for the months it touched.
class SummaryNotifier
    extends AutoDisposeFamilyAsyncNotifier<MonthSummary, String> {
  @override
  Future<MonthSummary> build(String month) =>
      ref.watch(summaryRepositoryProvider).fetchSummary(month);

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
