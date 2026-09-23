import 'package:flutter/foundation.dart';

import '../domain/transaction.dart';

/// One section of the feed: a calendar day and the transactions on it.
@immutable
class DayGroup {
  const DayGroup({
    required this.day,
    required this.items,
    required this.totalPaise,
  });

  /// Local midnight. Transactions are already in local time, so this is the
  /// day the customer remembers paying on, not the server's UTC date.
  final DateTime day;

  /// In the order they were given. Unmodifiable.
  final List<Transaction> items;

  /// The signed sum of [items], with the same sign convention as a row: a day
  /// of spending is negative and a day of nothing but refunds is positive. The
  /// header total is then literally the rows beneath it added up.
  final int totalPaise;

  /// [totalPaise] as spend, the way the rest of the app counts it.
  int get spentPaise => -totalPaise;

  DayGroup copyWith({
    DateTime? day,
    List<Transaction>? items,
    int? totalPaise,
  }) {
    return DayGroup(
      day: day ?? this.day,
      items: items ?? this.items,
      totalPaise: totalPaise ?? this.totalPaise,
    );
  }

  @override
  String toString() =>
      'DayGroup(${day.year}-${day.month}-${day.day}, items: ${items.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayGroup &&
          other.day == day &&
          other.totalPaise == totalPaise &&
          listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(day, totalPaise, Object.hashAll(items));
}

/// Splits a feed into one [DayGroup] per local calendar day.
///
/// Groups come out in the order their first transaction appears, so a feed
/// sorted newest first gives newest-day-first sections. A day that shows up
/// in two separate runs of the input is still one group, not two headers with
/// the same date.
///
/// Pure and linear, with integer sums only, so it is safe to call from build.
List<DayGroup> groupByDay(List<Transaction> transactions) {
  final buckets = <DateTime, List<Transaction>>{};
  for (final txn in transactions) {
    final at = txn.at;
    buckets.putIfAbsent(DateTime(at.year, at.month, at.day), () => []).add(txn);
  }

  return [
    for (final MapEntry(key: day, value: items) in buckets.entries)
      DayGroup(
        day: day,
        items: List.unmodifiable(items),
        totalPaise: _sum(items),
      ),
  ];
}

int _sum(List<Transaction> items) {
  var total = 0;
  for (final txn in items) {
    total += txn.amountPaise;
  }
  return total;
}
