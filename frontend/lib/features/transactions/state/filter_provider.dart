import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/session_provider.dart';
import '../domain/transaction_filter.dart';

/// What the Spending tab is narrowed to.
///
/// App-wide on purpose: not auto-disposed and not owned by a screen, so
/// opening a transaction, switching tabs, or a feed screen being rebuilt from
/// scratch all find the filter exactly as the customer left it. The feed
/// reads it into its family key, so changing it is what fetches new rows.
///
/// Keyed to the customer, like the category list: signing in as someone else
/// starts unfiltered instead of inheriting another person's search.
///
/// Every method replaces the state with a new [TransactionFilter]; nothing
/// is changed in place.
class FilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() {
    ref.watch(sessionProvider.select((state) => state.session?.user.id));
    return TransactionFilter.none;
  }

  /// A category id, or null for every category.
  void setCategory(String? category) {
    state = state.copyWith(category: category);
  }

  /// Stored trimmed, so `swiggy` and `swiggy ` are one filter and one
  /// request rather than two.
  void setQuery(String query) {
    state = state.copyWith(query: query.trim());
  }

  /// Replaces the whole amount range, in paise. Leave an end null for "no
  /// bound"; call it with neither to remove the range.
  void setAmountRange({int? minPaise, int? maxPaise}) {
    assert(
      minPaise == null || maxPaise == null || minPaise <= maxPaise,
      'The minimum cannot be above the maximum.',
    );
    state = state.copyWith(minPaise: minPaise, maxPaise: maxPaise);
  }

  /// Replaces the whole date range; both ends inclusive, in local time. Call
  /// it with neither to remove the range.
  void setDateRange({DateTime? from, DateTime? to}) {
    assert(
      from == null || to == null || !to.isBefore(from),
      'The range cannot end before it starts.',
    );
    state = state.copyWith(from: from, to: to);
  }

  void clear() => state = TransactionFilter.none;

  /// Replaces everything in one step. This is how the filter sheet's result
  /// lands: one change, so one new feed and one request, rather than one per
  /// field the customer touched.
  void applyAll(TransactionFilter filter) => state = filter;

  /// An equal filter is the same feed, so there is nothing to tell anyone.
  @override
  bool updateShouldNotify(TransactionFilter previous, TransactionFilter next) =>
      previous != next;
}

final NotifierProvider<FilterNotifier, TransactionFilter> filterStateNotifier =
    NotifierProvider<FilterNotifier, TransactionFilter>(FilterNotifier.new);

/// How many filters are narrowing the feed — see
/// [TransactionFilter.activeCount]. The number on the filter button's badge,
/// and the number of chips above the list.
final Provider<int> activeFilterCountProvider = Provider<int>(
  (ref) =>
      ref.watch(filterStateNotifier.select((filter) => filter.activeCount)),
);
