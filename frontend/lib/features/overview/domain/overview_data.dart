import 'package:flutter/foundation.dart' hide Category;

import '../../../core/utils/date_format.dart';
import '../../../core/utils/json_read.dart';
import '../../categories/domain/category.dart';
import 'month_summary.dart';

/// The server's catch-all category. It never gets a slice of its own — it
/// joins the folded tail — so a donut can never show two slices both called
/// "Other".
const String otherCategoryId = 'other';

/// Categories that get their own slice before the rest fold into "Other".
const int maxNamedSlices = 6;

/// One slice of the spending donut, and one row of its table.
@immutable
class CategorySlice {
  const CategorySlice({
    required this.label,
    required this.paise,
    required this.sharePercent,
    this.category,
    this.argb,
  });

  /// The category to open the feed at, or null for a slice folding several
  /// categories together — there is no single feed to open for those.
  final String? category;

  final String label;

  /// Spend, always positive. A category whose refunds outweighed its
  /// spending has no slice: see [OverviewData.refundedCategories].
  final int paise;

  /// Whole percent of the charted spend, largest-remainder rounded so the
  /// slices of one donut always add up to exactly 100.
  final int sharePercent;

  /// Opaque ARGB for the slice's mark, or null for the neutral fold colour,
  /// which comes from the theme.
  final int? argb;

  bool get isFold => category == null;

  CategorySlice copyWith({
    String? category,
    String? label,
    int? paise,
    int? sharePercent,
    int? argb,
  }) {
    return CategorySlice(
      category: category ?? this.category,
      label: label ?? this.label,
      paise: paise ?? this.paise,
      sharePercent: sharePercent ?? this.sharePercent,
      argb: argb ?? this.argb,
    );
  }

  @override
  String toString() => 'CategorySlice(${category ?? 'fold'}, $sharePercent%)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategorySlice &&
          other.category == category &&
          other.label == label &&
          other.paise == paise &&
          other.sharePercent == sharePercent &&
          other.argb == argb;

  @override
  int get hashCode => Object.hash(category, label, paise, sharePercent, argb);
}

/// One row of a chart's table alternative. The amount stays in paise; the
/// table formats it, like every other widget.
@immutable
class ChartTableRow {
  const ChartTableRow({
    required this.label,
    required this.paise,
    this.sharePercent,
  });

  final String label;
  final int paise;
  final int? sharePercent;

  ChartTableRow copyWith({String? label, int? paise, int? sharePercent}) {
    return ChartTableRow(
      label: label ?? this.label,
      paise: paise ?? this.paise,
      sharePercent: sharePercent ?? this.sharePercent,
    );
  }

  @override
  String toString() => 'ChartTableRow($label)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartTableRow &&
          other.label == label &&
          other.paise == paise &&
          other.sharePercent == sharePercent;

  @override
  int get hashCode => Object.hash(label, paise, sharePercent);
}

/// Everything the Overview draws for one month, derived once from a
/// [MonthSummary] so no widget has to build a list during build.
@immutable
class OverviewData {
  const OverviewData({
    required this.summary,
    required this.slices,
    required this.days,
    required this.categoryRows,
    required this.dayRows,
    required this.refundedCategories,
  });

  /// Integer maths throughout; nothing here divides by a total that can be
  /// zero. [categories] supplies names and colours — an id it does not know
  /// still gets a readable name and the neutral colour.
  factory OverviewData.from(MonthSummary summary, List<Category> categories) {
    final slices = _slices(summary.byCategory, categories);
    final days = _everyDay(summary);

    return OverviewData(
      summary: summary,
      slices: slices,
      days: days,
      categoryRows: List.unmodifiable([
        for (final slice in slices)
          ChartTableRow(
            label: slice.label,
            paise: slice.paise,
            sharePercent: slice.sharePercent,
          ),
      ]),
      dayRows: List.unmodifiable([
        for (final day in days)
          ChartTableRow(label: shortDateLabel(day.date), paise: day.paise),
      ]),
      refundedCategories: List.unmodifiable([
        for (final MapEntry(key: id, value: paise)
            in _bySpend(summary.byCategory))
          if (paise < 0) categories.nameOf(id),
      ]),
    );
  }

  final MonthSummary summary;

  /// At most [maxNamedSlices] categories, largest first, then the fold.
  /// Unmodifiable.
  final List<CategorySlice> slices;

  /// Every day of the month, ascending, zero-filled — the server leaves out
  /// the days nothing happened on, and a chart with gaps reads as missing
  /// data. Unmodifiable.
  final List<DailyTotal> days;

  /// [slices] as table rows, same order, same numbers.
  final List<ChartTableRow> categoryRows;

  /// [days] as table rows.
  final List<ChartTableRow> dayRows;

  /// Categories whose refunds outweighed their spending, by name. They count
  /// towards the month's total but cannot be drawn as a slice.
  final List<String> refundedCategories;

  bool get isEmpty => summary.isEmpty;

  /// What the donut adds up to: positive category spend only.
  int get chartedPaise {
    var total = 0;
    for (final slice in slices) {
      total += slice.paise;
    }
    return total;
  }

  OverviewData copyWith({
    MonthSummary? summary,
    List<CategorySlice>? slices,
    List<DailyTotal>? days,
    List<ChartTableRow>? categoryRows,
    List<ChartTableRow>? dayRows,
    List<String>? refundedCategories,
  }) {
    return OverviewData(
      summary: summary ?? this.summary,
      slices: slices ?? this.slices,
      days: days ?? this.days,
      categoryRows: categoryRows ?? this.categoryRows,
      dayRows: dayRows ?? this.dayRows,
      refundedCategories: refundedCategories ?? this.refundedCategories,
    );
  }

  @override
  String toString() => 'OverviewData(${summary.month}, '
      'slices: ${slices.length}, days: ${days.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverviewData &&
          other.summary == summary &&
          listEquals(other.slices, slices) &&
          listEquals(other.days, days) &&
          listEquals(other.categoryRows, categoryRows) &&
          listEquals(other.dayRows, dayRows) &&
          listEquals(other.refundedCategories, refundedCategories);

  @override
  int get hashCode => Object.hash(
        summary,
        Object.hashAll(slices),
        Object.hashAll(days),
        Object.hashAll(categoryRows),
        Object.hashAll(dayRows),
        Object.hashAll(refundedCategories),
      );
}

/// Entries largest spend first, ties by id: the server's map arrives in
/// whatever order it built it, and the donut must not reshuffle between two
/// fetches of the same numbers.
List<MapEntry<String, int>> _bySpend(Map<String, int> byCategory) {
  return byCategory.entries.toList()
    ..sort((a, b) {
      final bySpend = b.value.compareTo(a.value);
      return bySpend != 0 ? bySpend : a.key.compareTo(b.key);
    });
}

List<CategorySlice> _slices(
  Map<String, int> byCategory,
  List<Category> categories,
) {
  final spent = [
    for (final entry in _bySpend(byCategory))
      if (entry.value > 0) entry,
  ];
  final named = [
    for (final entry in spent)
      if (entry.key != otherCategoryId) entry,
  ].take(maxNamedSlices).toList();
  final namedIds = {for (final entry in named) entry.key};
  final tail = [
    for (final entry in spent)
      if (!namedIds.contains(entry.key)) entry,
  ];

  // A tail of one is not a fold: it is that category, under its own name.
  final (String?, String, int, int?)? fold = switch (tail) {
    [] => null,
    [final only] => (
        only.key,
        categories.nameOf(only.key),
        only.value,
        categories.byId(only.key)?.argb,
      ),
    _ => (null, 'Other', _sum(tail), null),
  };

  final amounts = [
    for (final entry in named) entry.value,
    if (fold != null) fold.$3,
  ];
  final shares = _largestRemainderPercent(amounts);

  return List.unmodifiable([
    for (final (index, entry) in named.indexed)
      CategorySlice(
        category: entry.key,
        label: categories.nameOf(entry.key),
        paise: entry.value,
        sharePercent: shares[index],
        argb: categories.byId(entry.key)?.argb,
      ),
    if (fold case (final id, final label, final paise, final argb))
      CategorySlice(
        category: id,
        label: label,
        paise: paise,
        sharePercent: shares.last,
        argb: argb,
      ),
  ]);
}

int _sum(List<MapEntry<String, int>> entries) {
  var total = 0;
  for (final entry in entries) {
    total += entry.value;
  }
  return total;
}

/// Whole percentages of [amounts] that add up to exactly 100.
///
/// Each share is truncated, then the points lost to truncation go one at a
/// time to the largest remainders — ties to the earlier (larger) slice. All
/// integer: `amount * 100` stays far inside 64 bits for any real month. With
/// nothing to share, every share is zero rather than a division by zero.
List<int> _largestRemainderPercent(List<int> amounts) {
  final total = amounts.fold<int>(0, (sum, amount) => sum + amount);
  if (total <= 0) return List.filled(amounts.length, 0);

  final shares = [for (final amount in amounts) amount * 100 ~/ total];
  var unallocated = 100 - shares.fold<int>(0, (sum, share) => sum + share);

  final byRemainder = List<int>.generate(amounts.length, (i) => i)
    ..sort((a, b) {
      final remainder =
          (amounts[b] * 100 % total).compareTo(amounts[a] * 100 % total);
      return remainder != 0 ? remainder : a.compareTo(b);
    });
  for (final index in byRemainder) {
    if (unallocated == 0) break;
    shares[index] += 1;
    unallocated -= 1;
  }
  return shares;
}

List<DailyTotal> _everyDay(MonthSummary summary) {
  final start = parseMonthKey(summary.month);
  final dayCount = DateTime(start.year, start.month + 1, 0).day;

  final byDate = <String, int>{};
  for (final day in summary.byDay) {
    final key = isoLocalDate(day.date);
    byDate[key] = (byDate[key] ?? 0) + day.paise;
  }

  return List.unmodifiable([
    for (var day = 1; day <= dayCount; day++)
      DailyTotal(
        date: DateTime(start.year, start.month, day),
        paise:
            byDate[isoLocalDate(DateTime(start.year, start.month, day))] ?? 0,
      ),
  ]);
}
