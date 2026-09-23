import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import '../domain/transaction_filter.dart';
import '../domain/transaction_page.dart';

/// Distinguishes "leave the field alone" from "clear it" in the copyWiths.
const Object _unset = Object();

/// Which feed: a month, narrowed by a filter. The family key for
/// [feedProvider], so two equal keys share one feed and one set of requests.
@immutable
class FeedKey {
  const FeedKey({required this.month, this.filter = TransactionFilter.none});

  /// `YYYY-MM`.
  final String month;
  final TransactionFilter filter;

  FeedKey copyWith({String? month, TransactionFilter? filter}) {
    return FeedKey(month: month ?? this.month, filter: filter ?? this.filter);
  }

  @override
  String toString() => 'FeedKey($month, $filter)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedKey && other.month == month && other.filter == filter;

  @override
  int get hashCode => Object.hash(month, filter);
}

/// Everything the feed has loaded so far, and whether it is fetching more.
@immutable
class FeedState {
  const FeedState({
    this.items = const [],
    this.nextCursor,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  factory FeedState.firstPage(TransactionPage page) {
    return FeedState(items: page.items, nextCursor: page.nextCursor);
  }

  /// Every loaded row, newest first. Unmodifiable, and replaced wholesale on
  /// each page: a list a widget is holding never changes under it.
  final List<Transaction> items;

  /// Where the next page starts; null once the last page is in.
  final String? nextCursor;

  final bool isLoadingMore;

  /// Why the last [FeedNotifier.loadMore] failed, if it did.
  ///
  /// Kept here rather than turning the whole feed into an `AsyncError`: a
  /// failed page 3 must not throw away pages 1 and 2. The footer shows it with
  /// its own Retry.
  final BankError? loadMoreError;

  /// Derived rather than stored, so it can never disagree with [nextCursor].
  bool get hasMore => nextCursor != null;

  /// The loaded row with [id], or null.
  Transaction? find(String id) {
    for (final txn in items) {
      if (txn.id == id) return txn;
    }
    return null;
  }

  /// A new state with [page] after the rows already here.
  FeedState appendPage(TransactionPage page) {
    return FeedState(
      items: List.unmodifiable([...items, ...page.items]),
      nextCursor: page.nextCursor,
    );
  }

  FeedState copyWith({
    List<Transaction>? items,
    Object? nextCursor = _unset,
    bool? isLoadingMore,
    Object? loadMoreError = _unset,
  }) {
    return FeedState(
      items: items ?? this.items,
      nextCursor: identical(nextCursor, _unset)
          ? this.nextCursor
          : nextCursor as String?,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: identical(loadMoreError, _unset)
          ? this.loadMoreError
          : loadMoreError as BankError?,
    );
  }

  /// No cursor and no rows: the cursor encodes a transaction id.
  @override
  String toString() => 'FeedState(items: ${items.length}, hasMore: $hasMore, '
      'isLoadingMore: $isLoadingMore, failed: ${loadMoreError != null})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedState &&
          other.nextCursor == nextCursor &&
          other.isLoadingMore == isLoadingMore &&
          other.loadMoreError == loadMoreError &&
          listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(items),
        nextCursor,
        isLoadingMore,
        loadMoreError,
      );
}

/// The paged transaction feed for one [FeedKey].
///
/// Page one is `build`, so it gets `AsyncValue`'s loading and error states for
/// free. Later pages are appended to the data and never replace it.
class FeedNotifier extends AutoDisposeFamilyAsyncNotifier<FeedState, FeedKey> {
  static const int pageSize = TransactionRepository.defaultPageSize;

  /// Bumped whenever this feed is rebuilt or disposed. A page that was
  /// requested under an older generation belongs to a list that no longer
  /// exists, and is dropped when it lands.
  int _generation = 0;

  @override
  Future<FeedState> build(FeedKey key) async {
    final registry = ref.watch(feedRegistryProvider).._add(key);
    ref.onDispose(() {
      _generation++;
      registry._remove(key);
    });

    final page = await ref.watch(transactionRepositoryProvider).fetchPage(
          month: key.month,
          filter: key.filter,
          limit: pageSize,
        );
    return FeedState.firstPage(page);
  }

  /// Fetches the next page and appends it.
  ///
  /// A no-op while page one is loading or refreshing, while another page is
  /// already on its way, and once the last page is in — so it is safe to call
  /// on every scroll event.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (state.isLoading || current == null) return;
    if (!current.hasMore || current.isLoadingMore) return;

    final generation = _generation;
    final loading = current.copyWith(isLoadingMore: true, loadMoreError: null);
    state = AsyncData(loading);

    try {
      final page = await ref.read(transactionRepositoryProvider).fetchPage(
            month: arg.month,
            filter: arg.filter,
            cursor: current.nextCursor,
            limit: pageSize,
          );
      if (generation != _generation) return;
      // Onto the rows as they are now, not as they were when the request went
      // out: a row recategorised while the page was in flight keeps its new
      // category.
      state = AsyncData(_latest(loading).appendPage(page));
    } on BankError catch (error) {
      if (generation != _generation) return;
      state = AsyncData(
        _latest(loading).copyWith(isLoadingMore: false, loadMoreError: error),
      );
    }
  }

  FeedState _latest(FeedState fallback) => state.valueOrNull ?? fallback;

  /// Moves every loaded row [where] picks to [category], on this frame.
  ///
  /// Returns the category each moved row had before, keyed by id, so the
  /// caller can later put exactly those rows back. Rows already in [category]
  /// are left alone and not reported.
  ///
  /// A feed with rows is touched even mid-refresh: they stay on screen under
  /// the spinner, so they should show the change, and the refresh replaces
  /// them with the server's copy when it lands. A feed still loading its
  /// first page, or showing an error, has no rows on screen to patch.
  Map<String, String> applyCategory(
    String category, {
    required bool Function(Transaction txn) where,
  }) {
    final current = _settled;
    if (current == null) return const {};

    final previous = <String, String>{};
    final items = List<Transaction>.of(current.items);
    for (var i = 0; i < items.length; i++) {
      final txn = items[i];
      if (txn.category == category || !where(txn)) continue;
      previous[txn.id] = txn.category;
      items[i] = txn.copyWith(category: category);
    }

    if (previous.isEmpty) return const {};
    state = AsyncData(current.copyWith(items: List.unmodifiable(items)));
    return Map.unmodifiable(previous);
  }

  /// Puts back what [applyCategory] moved: each row in [previous] returns to
  /// the category recorded for it, provided it still shows [ifStill].
  ///
  /// A row showing anything else has been replaced since — by a refresh, say
  /// — and the server's newer copy is left alone.
  void restoreCategories(
    Map<String, String> previous, {
    required String ifStill,
  }) {
    final current = _settled;
    if (current == null || previous.isEmpty) return;

    var changed = false;
    final items = List<Transaction>.of(current.items);
    for (var i = 0; i < items.length; i++) {
      final txn = items[i];
      final before = previous[txn.id];
      if (before == null || txn.category != ifStill) continue;
      items[i] = txn.copyWith(category: before);
      changed = true;
    }

    if (changed) {
      state = AsyncData(current.copyWith(items: List.unmodifiable(items)));
    }
  }

  FeedState? get _settled => switch (state) {
        AsyncData(:final value) => value,
        _ => null,
      };

  /// Throws everything away and loads page one again.
  ///
  /// The rows stay on screen while it runs. Completes when the new page one
  /// has landed or failed; a failure is in [state], so the future itself never
  /// fails and pull-to-refresh can await it.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } on BankError {
      // Already in state as an AsyncError; the screen renders it.
    }
  }
}

/// Which feeds exist right now.
///
/// A recategorisation has to reach every loaded copy of a transaction, and a
/// provider family cannot list its members, so each feed signs in here when
/// it builds and out when it is disposed.
///
/// A service object like the Dio client, not state: nothing watches it for
/// changes, and it holds keys, never rows.
class FeedRegistry {
  final Set<FeedKey> _live = {};

  /// A snapshot, so a caller can loop over it while feeds come and go.
  Set<FeedKey> get liveKeys => Set.unmodifiable(_live);

  void _add(FeedKey key) => _live.add(key);

  void _remove(FeedKey key) => _live.remove(key);
}

final Provider<FeedRegistry> feedRegistryProvider =
    Provider<FeedRegistry>((ref) => FeedRegistry());

final AutoDisposeAsyncNotifierProviderFamily<FeedNotifier, FeedState, FeedKey>
    feedProvider =
    AsyncNotifierProvider.autoDispose.family<FeedNotifier, FeedState, FeedKey>(
  FeedNotifier.new,
);
