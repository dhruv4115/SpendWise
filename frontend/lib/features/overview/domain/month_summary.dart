import 'package:flutter/foundation.dart';

import '../../../core/utils/json_read.dart';

/// One bar on the daily chart: a calendar day and what was spent on it.
@immutable
class DailyTotal {
  const DailyTotal({required this.date, required this.paise});

  factory DailyTotal.fromJson(Map<String, dynamic> json) {
    return DailyTotal(
      date: readLocalDate(json, 'date'),
      paise: readInt(json, 'paise'),
    );
  }

  /// Local midnight on the day. A date has no time zone to convert.
  final DateTime date;

  /// Spend for the day: sign already flipped, negative on a day whose refunds
  /// outweighed its spends.
  final int paise;

  Map<String, Object?> toJson() => {
        'date': isoLocalDate(date),
        'paise': paise,
      };

  DailyTotal copyWith({DateTime? date, int? paise}) {
    return DailyTotal(date: date ?? this.date, paise: paise ?? this.paise);
  }

  @override
  String toString() => 'DailyTotal(${isoLocalDate(date)}: $paise)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyTotal && other.date == date && other.paise == paise;

  @override
  int get hashCode => Object.hash(date, paise);
}

/// Everything the Overview screen needs about one month.
///
/// All amounts are spend: `-sum(amountPaise)`, so a refund pulls a total down.
/// [totalPaise] can legitimately be negative in a month of returns.
@immutable
class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.totalPaise,
    required this.prevTotalPaise,
    required this.byCategory,
    required this.byDay,
  });

  factory MonthSummary.fromJson(Map<String, dynamic> json) {
    return MonthSummary(
      month: readString(json, 'month'),
      totalPaise: readInt(json, 'totalPaise'),
      prevTotalPaise: readIntOr(json, 'prevTotalPaise', 0),
      byCategory: readIntMap(json, 'byCategory'),
      byDay: readObjectList(json, 'byDay', DailyTotal.fromJson),
    );
  }

  /// An entirely empty month, for a first frame that needs a shape to render.
  static const MonthSummary empty = MonthSummary(
    month: '',
    totalPaise: 0,
    prevTotalPaise: 0,
    byCategory: {},
    byDay: [],
  );

  /// `YYYY-MM`.
  final String month;

  final int totalPaise;

  /// The same figure for the month before, so the header can say "up 12%"
  /// without a second request.
  final int prevTotalPaise;

  /// Category id to spend. Ordered by spend, largest first.
  final Map<String, int> byCategory;

  /// Every day of the month, ascending, zero-filled — a chart must not have
  /// gaps where nothing was spent.
  final List<DailyTotal> byDay;

  /// Change against the previous month, in paise. Positive means more spent.
  int get deltaPaise => totalPaise - prevTotalPaise;

  /// Change as a whole-number percentage, or null when there is no previous
  /// month to compare against and the question is meaningless.
  int? get deltaPercent {
    if (prevTotalPaise <= 0) return null;
    return deltaPaise * 100 ~/ prevTotalPaise;
  }

  bool get isEmpty => byCategory.isEmpty && totalPaise == 0;

  Map<String, Object?> toJson() => {
        'month': month,
        'totalPaise': totalPaise,
        'prevTotalPaise': prevTotalPaise,
        'byCategory': byCategory,
        'byDay': [for (final day in byDay) day.toJson()],
      };

  MonthSummary copyWith({
    String? month,
    int? totalPaise,
    int? prevTotalPaise,
    Map<String, int>? byCategory,
    List<DailyTotal>? byDay,
  }) {
    return MonthSummary(
      month: month ?? this.month,
      totalPaise: totalPaise ?? this.totalPaise,
      prevTotalPaise: prevTotalPaise ?? this.prevTotalPaise,
      byCategory: byCategory ?? this.byCategory,
      byDay: byDay ?? this.byDay,
    );
  }

  @override
  String toString() => 'MonthSummary($month, categories: ${byCategory.length}, '
      'days: ${byDay.length})';

  /// Deep equality: the collections are the value, so two summaries built from
  /// the same transactions must compare equal even though the maps and lists
  /// are different instances.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonthSummary &&
          other.month == month &&
          other.totalPaise == totalPaise &&
          other.prevTotalPaise == prevTotalPaise &&
          mapEquals(other.byCategory, byCategory) &&
          listEquals(other.byDay, byDay);

  @override
  int get hashCode => Object.hash(
        month,
        totalPaise,
        prevTotalPaise,
        // Unordered: two maps with the same entries are the same summary,
        // whatever order they were built in.
        Object.hashAllUnordered(
          byCategory.entries.map((e) => Object.hash(e.key, e.value)),
        ),
        Object.hashAll(byDay),
      );
}
