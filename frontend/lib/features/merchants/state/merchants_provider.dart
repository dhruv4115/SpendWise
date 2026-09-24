import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_filter.dart';
import '../../transactions/state/feed_provider.dart';
import '../data/merchant_repository.dart';
import '../domain/merchant_insight.dart';
import '../domain/merchant_rule.dart';

/// One month's merchant roll-up, keyed by `YYYY-MM`.
///
/// Each row names its merchant's top category, so a recategorisation
/// invalidates this for the months it touched.
final AutoDisposeFutureProviderFamily<List<MerchantInsight>, String>
    merchantsProvider =
    FutureProvider.autoDispose.family<List<MerchantInsight>, String>(
  (ref, month) => ref.watch(merchantRepositoryProvider).fetchMerchants(month),
);

extension MerchantInsightLookup on List<MerchantInsight> {
  /// The row for [merchantKey], or null when this month has nothing from
  /// that merchant.
  MerchantInsight? byKey(String merchantKey) {
    for (final insight in this) {
      if (insight.merchantKey == merchantKey) return insight;
    }
    return null;
  }
}

/// What the customer has ordered the merchants list by.
///
/// Three questions, not three columns: who takes the most of my money, who do
/// I go to most often, and who costs the most each time.
enum MerchantSort { total, visits, average }

/// The order the list starts in: biggest spender first, which is the answer
/// to the question the screen exists to ask.
class MerchantSortNotifier extends Notifier<MerchantSort> {
  @override
  MerchantSort build() => MerchantSort.total;

  void set(MerchantSort sort) => state = sort;
}

final NotifierProvider<MerchantSortNotifier, MerchantSort>
    merchantSortProvider = NotifierProvider<MerchantSortNotifier, MerchantSort>(
  MerchantSortNotifier.new,
);

/// [merchants] in [sort] order, biggest first, as a new unmodifiable list.
///
/// Every order is total-descending underneath, and every tie is broken by the
/// merchant key: two merchants with one visit each must not swap places
/// between two builds of the same screen.
List<MerchantInsight> sortMerchants(
  List<MerchantInsight> merchants,
  MerchantSort sort,
) {
  int byTotal(MerchantInsight a, MerchantInsight b) =>
      b.totalPaise.compareTo(a.totalPaise);
  int byKey(MerchantInsight a, MerchantInsight b) =>
      a.merchantKey.compareTo(b.merchantKey);

  final ordered = List<MerchantInsight>.of(merchants)
    ..sort((a, b) {
      final first = switch (sort) {
        MerchantSort.total => byTotal(a, b),
        MerchantSort.visits => b.visits.compareTo(a.visits),
        MerchantSort.average => b.avgPaise.compareTo(a.avgPaise),
      };
      if (first != 0) return first;
      final second = byTotal(a, b);
      return second != 0 ? second : byKey(a, b);
    });
  return List.unmodifiable(ordered);
}

/// The month's merchants, in the order the customer asked for.
///
/// A plain [Provider] rather than a second request: re-sorting is a transform
/// of what has already arrived, so changing the order never shows a spinner
/// and never touches the network.
final AutoDisposeProviderFamily<AsyncValue<List<MerchantInsight>>, String>
    sortedMerchantsProvider =
    Provider.autoDispose.family<AsyncValue<List<MerchantInsight>>, String>(
  (ref, month) {
    final sort = ref.watch(merchantSortProvider);
    return ref
        .watch(merchantsProvider(month))
        .whenData((merchants) => sortMerchants(merchants, sort));
  },
);

/// Which merchant, in which month. The family key for [merchantRowsProvider].
///
/// The name is part of it because it is what the server searches on: the key
/// is ours, `q` is theirs.
@immutable
class MerchantMonthKey {
  const MerchantMonthKey({
    required this.month,
    required this.merchantKey,
    required this.merchantName,
  });

  /// `YYYY-MM`.
  final String month;
  final String merchantKey;
  final String merchantName;

  MerchantMonthKey copyWith({
    String? month,
    String? merchantKey,
    String? merchantName,
  }) {
    return MerchantMonthKey(
      month: month ?? this.month,
      merchantKey: merchantKey ?? this.merchantKey,
      merchantName: merchantName ?? this.merchantName,
    );
  }

  @override
  String toString() => 'MerchantMonthKey($merchantKey, $month)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MerchantMonthKey &&
          other.month == month &&
          other.merchantKey == merchantKey &&
          other.merchantName == merchantName;

  @override
  int get hashCode => Object.hash(month, merchantKey, merchantName);
}

/// One merchant's month: what they charged, and what it is filed as.
@immutable
class MerchantRows {
  const MerchantRows({
    required this.transactions,
    required this.isComplete,
    this.rule,
  });

  /// Newest first. Unmodifiable.
  final List<Transaction> transactions;

  /// Whether these are all of the month's rows for this merchant. False when
  /// the server had more than one page of them to give.
  final bool isComplete;

  /// The category every one of this merchant's payments is in — the rule a
  /// "change category for all" leaves behind. Null when they are spread over
  /// more than one category, or when [isComplete] is false and a row on the
  /// next page could still disagree.
  final MerchantRule? rule;

  bool get isEmpty => transactions.isEmpty;

  @override
  String toString() =>
      'MerchantRows(${transactions.length}, rule: ${rule?.category})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MerchantRows &&
          other.isComplete == isComplete &&
          other.rule == rule &&
          listEquals(other.transactions, transactions);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(transactions), isComplete, rule);
}

/// The rule [transactions] imply for [merchantKey], or null when there is
/// none.
///
/// The app has no endpoint to ask: `GET /merchants` reports a top category,
/// which is a majority, not a rule. So the rule is read off the rows
/// themselves — every payment in one category is exactly the state that
/// applying a category to a whole merchant leaves behind, and it is the only
/// claim the data supports.
MerchantRule? merchantRuleFor(
  String merchantKey,
  List<Transaction> transactions,
) {
  if (transactions.isEmpty) return null;

  final category = transactions.first.category;
  for (final transaction in transactions) {
    if (transaction.category != category) return null;
  }
  return MerchantRule(merchantKey: merchantKey, category: category);
}

/// One merchant's transactions for a month.
///
/// Asked for as a search rather than filtered out of the month's whole feed:
/// page one of the month is its fifty newest rows, which for a merchant the
/// customer used on the 2nd would show nothing. The rows that come back are
/// still narrowed to this merchant key, because `q` matches names and two
/// merchants can share a word.
///
/// It goes through [feedProvider], so a recategorisation applied anywhere in
/// the app moves these rows on the same frame as every other copy of them.
final AutoDisposeFutureProviderFamily<MerchantRows, MerchantMonthKey>
    merchantRowsProvider =
    FutureProvider.autoDispose.family<MerchantRows, MerchantMonthKey>(
  (ref, key) async {
    final feed = await ref.watch(
      feedProvider(
        FeedKey(
          month: key.month,
          filter: TransactionFilter(query: key.merchantName),
        ),
      ).future,
    );

    final rows = List<Transaction>.unmodifiable([
      for (final transaction in feed.items)
        if (transaction.merchantKey == key.merchantKey) transaction,
    ]);
    return MerchantRows(
      transactions: rows,
      isComplete: !feed.hasMore,
      rule: feed.hasMore ? null : merchantRuleFor(key.merchantKey, rows),
    );
  },
);
