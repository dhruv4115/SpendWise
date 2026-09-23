import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/categories/domain/category.dart';
import 'package:spendwise/features/overview/data/aggregator.dart';
import 'package:spendwise/features/overview/domain/month_summary.dart';
import 'package:spendwise/features/overview/domain/overview_data.dart';

import '../helpers/categories.dart';
import '../helpers/transactions.dart';

final List<Category> _categories = [
  for (final json in seededCategories) Category.fromJson(json),
];

MonthSummary _summary(
  Map<String, int> byCategory, {
  int prevTotalPaise = 0,
  List<DailyTotal> byDay = const [],
}) {
  var total = 0;
  for (final paise in byCategory.values) {
    total += paise;
  }
  return MonthSummary(
    month: '2026-09',
    totalPaise: total,
    prevTotalPaise: prevTotalPaise,
    byCategory: byCategory,
    byDay: byDay,
  );
}

/// Nine categories with spend: six named, then health, travel and the
/// server's own "other" fold together.
const Map<String, int> _nine = {
  'travel': 15000,
  'food': 450000,
  'other': 5000,
  'groceries': 300000,
  'health': 20000,
  'transport': 120000,
  'entertainment': 30000,
  'shopping': 90000,
  'bills': 60000,
};

void main() {
  group('slices', () {
    test('the top six by spend, then one Other fold', () {
      final data = OverviewData.from(_summary(_nine), _categories);

      expect(
        [for (final slice in data.slices) slice.label],
        [
          'Food & Dining',
          'Groceries',
          'Transport',
          'Shopping',
          'Bills & Utilities',
          'Entertainment',
          'Other',
        ],
      );
      final fold = data.slices.last;
      expect(fold.isFold, isTrue);
      expect(fold.category, isNull, reason: 'no single feed to open');
      expect(fold.argb, isNull, reason: 'the theme supplies its neutral');
      expect(fold.paise, 20000 + 15000 + 5000);
      expect(data.slices.first.argb, 0xFFE8590C);
    });

    test('shares are whole percents that add up to exactly 100', () {
      final data = OverviewData.from(_summary(_nine), _categories);

      expect(
        [for (final slice in data.slices) slice.sharePercent],
        [41, 28, 11, 8, 5, 3, 4],
      );
      expect(
        data.slices.fold<int>(0, (sum, s) => sum + s.sharePercent),
        100,
      );
      expect(data.chartedPaise, 1090000);
    });

    test("the server's own 'other' never gets a second Other slice", () {
      final data = OverviewData.from(
        _summary({'other': 900000, 'food': 1000}),
        _categories,
      );

      expect(
          [for (final s in data.slices) s.label], ['Food & Dining', 'Other']);
      expect(data.slices.last.category, 'other',
          reason: 'a fold of one is that category, and can be opened');
    });

    test('a tail of one keeps its own name and colour', () {
      final data = OverviewData.from(
        _summary({..._nine}
          ..remove('other')
          ..remove('travel')),
        _categories,
      );

      expect(data.slices.last.label, 'Health');
      expect(data.slices.last.category, 'health');
      expect(data.slices.last.argb, 0xFF0CA678);
    });

    test('a category that refunds outweighed is listed, not charted', () {
      final data = OverviewData.from(
        _summary({'food': 50000, 'shopping': -20000}),
        _categories,
      );

      expect([for (final s in data.slices) s.category], ['food']);
      expect(data.slices.single.sharePercent, 100);
      expect(data.refundedCategories, ['Shopping']);
      expect(data.summary.totalPaise, 30000,
          reason: 'the total is not floored — only the drawing is');
    });

    test('ties break by id, so two fetches of one month draw alike', () {
      final one = OverviewData.from(
        _summary({'travel': 100, 'bills': 100, 'food': 100}),
        _categories,
      );
      final two = OverviewData.from(
        _summary({'food': 100, 'travel': 100, 'bills': 100}),
        _categories,
      );

      expect(one, two);
      expect([for (final s in one.slices) s.category],
          ['bills', 'food', 'travel']);
    });

    test('an id the category list does not know still reads well', () {
      final data = OverviewData.from(_summary({'pets': 1000}), const []);

      expect(data.slices.single.label, 'Pets');
      expect(data.slices.single.argb, isNull);
    });
  });

  group('days', () {
    test('every day of the month, zero-filled, from a sparse server list', () {
      final data = OverviewData.from(
        _summary(
          {'food': 4000},
          byDay: [
            DailyTotal(date: DateTime(2026, 9, 3), paise: 2500),
            DailyTotal(date: DateTime(2026, 9, 30), paise: 1500),
          ],
        ),
        _categories,
      );

      expect(data.days, hasLength(30));
      expect(data.days.first.date, DateTime(2026, 9, 1));
      expect(data.days[2].paise, 2500);
      expect(data.days.last.paise, 1500);
      expect(
        data.days.where((day) => day.paise != 0),
        hasLength(2),
      );
      expect(data.dayRows[2].label, '3 Sep');
      expect(data.dayRows[2].paise, 2500);
    });
  });

  test('an empty month yields zeros and divides by nothing', () {
    final empty = OverviewData.from(
      _summary(const {}, prevTotalPaise: 250000),
      _categories,
    );

    expect(empty.isEmpty, isTrue);
    expect(empty.slices, isEmpty);
    expect(empty.categoryRows, isEmpty);
    expect(empty.chartedPaise, 0);
    expect(empty.days, hasLength(30));
    expect(empty.days.every((day) => day.paise == 0), isTrue);
    expect(empty.summary.deltaPaise, -250000);
    expect(empty.summary.deltaPercent, -100);

    final nothingBefore = OverviewData.from(_summary(const {}), _categories);
    expect(nothingBefore.summary.deltaPercent, isNull,
        reason: 'no previous month to divide by');
  });

  test('the table rows are the chart numbers, in the chart order', () {
    final data = OverviewData.from(_summary(_nine), _categories);

    expect(data.categoryRows, hasLength(data.slices.length));
    for (final (index, slice) in data.slices.indexed) {
      expect(data.categoryRows[index].label, slice.label);
      expect(data.categoryRows[index].paise, slice.paise);
      expect(data.categoryRows[index].sharePercent, slice.sharePercent);
    }
  });

  test('the stress month is summarised and charted well inside 300 ms', () {
    // 5,200 rows across 30 days and every category — the seed's biggest.
    final rows = [
      for (var i = 0; i < 5200; i++)
        txn(
          id: 'txn_$i',
          merchantName: 'Merchant ${i % 40}',
          category: seededCategories[i % 10]['id']! as String,
          amountPaise: i % 33 == 0 ? 1500 : -(1000 + i),
          at: DateTime(2026, 9, 1 + i % 30, 12),
        ),
    ];

    final clock = Stopwatch()..start();
    final data = OverviewData.from(
      Aggregator.summarise(rows, '2026-09'),
      _categories,
    );
    clock.stop();

    expect(data.slices, hasLength(maxNamedSlices + 1));
    expect(clock.elapsedMilliseconds, lessThan(300));
  });
}
