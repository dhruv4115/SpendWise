/// The aggregation core: every number the Overview and Merchants screens show
/// is computed here.
///
/// Deliberately free of Flutter — no widgets, no `BuildContext`, no plugins —
/// so it runs unchanged in a background isolate and can be tested as plain
/// Dart. It is also free of `double`: every total is integer paise, added and
/// divided with integer operators only, so a month of 5,200 transactions comes
/// out to the exact paise rather than to within a rounding error.
///
/// "Spent" is `-sum(amountPaise)` throughout: debits are negative on the wire,
/// so flipping the sign makes spend positive and lets a refund pull a total
/// back down.
library;

import '../../../core/utils/date_format.dart';
import '../../merchants/domain/merchant_insight.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/month_summary.dart';

abstract final class Aggregator {
  /// Rolls a month's transactions into everything Overview renders.
  ///
  /// [txns] is expected to be one month's worth; nothing is filtered out, so
  /// the totals are of exactly what is handed in. [prevTotalPaise] comes from
  /// the caller — the previous month is a separate fetch, not something this
  /// function can work out on its own.
  ///
  /// Throws [FormatException] if [month] is not `YYYY-MM`.
  static MonthSummary summarise(
    List<Transaction> txns,
    String month, {
    int prevTotalPaise = 0,
  }) {
    return MonthSummary(
      month: month,
      totalPaise: totalSpentPaise(txns),
      prevTotalPaise: prevTotalPaise,
      byCategory: byCategory(txns),
      byDay: byDay(txns, month),
    );
  }

  /// Total spend across [txns]. Negative if refunds outweighed spends.
  static int totalSpentPaise(List<Transaction> txns) {
    var total = 0;
    for (final txn in txns) {
      total += txn.spentPaise;
    }
    return total;
  }

  /// Category id to spend, largest spend first, ties broken by id so the
  /// order is stable between rebuilds and between runs.
  ///
  /// A refund reduces its own category's total and can take it negative; that
  /// is deliberate, and only the display layer floors it at zero.
  static Map<String, int> byCategory(List<Transaction> txns) {
    final totals = <String, int>{};
    for (final txn in txns) {
      totals[txn.category] = (totals[txn.category] ?? 0) + txn.spentPaise;
    }

    final ordered = totals.keys.toList()
      ..sort((a, b) {
        final byAmount = totals[b]!.compareTo(totals[a]!);
        return byAmount != 0 ? byAmount : a.compareTo(b);
      });

    return {for (final category in ordered) category: totals[category]!};
  }

  /// Every day of [month], ascending, zero-filled.
  ///
  /// A chart with holes in it reads as missing data rather than as a quiet
  /// day, so days with no spending are present with a zero.
  ///
  /// Transactions are bucketed by their *local* date, which is the date the
  /// customer remembers the payment happening on. A payment made late on the
  /// last night of the month can therefore fall outside [month] once converted
  /// — it still counts towards [totalSpentPaise], but it has no bar to sit on
  /// and is left out here rather than being pushed onto a day it did not
  /// happen.
  ///
  /// Throws [FormatException] if [month] is not `YYYY-MM`.
  static List<DailyTotal> byDay(List<Transaction> txns, String month) {
    final start = parseMonthKey(month);
    // Day zero of the next month is the last day of this one — leap years
    // included, without a table of month lengths.
    final dayCount = DateTime(start.year, start.month + 1, 0).day;

    final totals = List<int>.filled(dayCount, 0);
    for (final txn in txns) {
      final at = txn.at;
      if (at.year != start.year || at.month != start.month) continue;
      totals[at.day - 1] += txn.spentPaise;
    }

    return [
      for (var day = 1; day <= dayCount; day++)
        DailyTotal(
          date: DateTime(start.year, start.month, day),
          paise: totals[day - 1],
        ),
    ];
  }

  /// One row per merchant, biggest spender first.
  ///
  /// Ties break on [MerchantInsight.merchantKey] ascending, matching the
  /// server's ordering so a locally computed list and a fetched one agree.
  static List<MerchantInsight> merchantInsights(List<Transaction> txns) {
    final tallies = <String, _MerchantTally>{};

    for (final txn in txns) {
      final tally = tallies.putIfAbsent(
        txn.merchantKey,
        () => _MerchantTally(txn.merchantKey, txn.merchantName, txn.at),
      );
      tally.add(txn);
    }

    final insights = [
      for (final tally in tallies.values)
        MerchantInsight(
          merchantKey: tally.merchantKey,
          merchantName: tally.merchantName,
          totalPaise: tally.totalPaise,
          visits: tally.visits,
          // Integer division, truncating towards zero: paise do not subdivide,
          // and an average is a display figure, never an input to a total.
          avgPaise: tally.totalPaise ~/ tally.visits,
          topCategory: tally.topCategory,
        ),
    ]..sort((a, b) {
        final byTotal = b.totalPaise.compareTo(a.totalPaise);
        return byTotal != 0 ? byTotal : a.merchantKey.compareTo(b.merchantKey);
      });

    return insights;
  }

  /// Collapses a card network's descriptor to a stable merchant key.
  ///
  /// `SWIGGY*1234`, `SWIGGY *8891` and `swiggy-2201` are one merchant, so all
  /// three must produce `swiggy`. This mirrors the server's rule exactly —
  /// uppercase, replace runs of digits, `*` and `-` with a space, collapse
  /// whitespace, trim, lowercase — because a key computed here is compared
  /// against keys computed there.
  static String normaliseMerchant(String raw) => raw
      .toUpperCase()
      .replaceAll(_noise, ' ')
      .replaceAll(_whitespace, ' ')
      .trim()
      .toLowerCase();

  static final RegExp _noise = RegExp(r'[0-9*-]+');
  static final RegExp _whitespace = RegExp(r'\s+');
}

/// Running totals for one merchant while [Aggregator.merchantInsights] walks
/// the list. Mutable and private: it never leaves this file.
class _MerchantTally {
  _MerchantTally(this.merchantKey, this._name, this._lastSeen);

  final String merchantKey;
  final Map<String, int> _byCategory = {};

  String _name;
  DateTime _lastSeen;

  int totalPaise = 0;
  int visits = 0;

  /// The most recent spelling of the name, so a merchant that has been
  /// rebranded shows as what it is called now.
  String get merchantName => _name;

  void add(Transaction txn) {
    totalPaise += txn.spentPaise;
    visits += 1;
    _byCategory[txn.category] =
        (_byCategory[txn.category] ?? 0) + txn.spentPaise;

    if (txn.at.isAfter(_lastSeen)) {
      _lastSeen = txn.at;
      _name = txn.merchantName;
    }
  }

  /// The category this merchant's spend mostly went to. Ties break on the
  /// category id so the answer does not depend on map iteration order.
  String get topCategory {
    late String best;
    var bestPaise = 0;
    var first = true;

    for (final entry in _byCategory.entries) {
      if (first ||
          entry.value > bestPaise ||
          (entry.value == bestPaise && entry.key.compareTo(best) < 0)) {
        best = entry.key;
        bestPaise = entry.value;
        first = false;
      }
    }
    return best;
  }
}
