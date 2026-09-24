import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/overview/data/aggregator.dart';
import 'package:spendwise/features/overview/data/summarise_async.dart';
import 'package:spendwise/features/overview/domain/month_summary.dart';
import 'package:spendwise/features/transactions/domain/transaction.dart';

import '../helpers/transactions.dart';

const String _month = '2026-09';

const List<String> _categories = [
  'food',
  'groceries',
  'transport',
  'shopping',
  'bills',
  'entertainment',
  'health',
];

/// [count] rows spread across the whole of September, in seven categories and
/// nine merchants, with a refund every seventeenth row so the totals are not
/// simply a sum of one sign.
///
/// Deliberately not random: a failure here has to be reproducible.
List<Transaction> _rows(int count) {
  return [
    for (var i = 0; i < count; i++)
      txn(
        id: 'txn_${i.toString().padLeft(5, '0')}',
        merchantName: 'Merchant ${i % 9}',
        category: _categories[i % _categories.length],
        amountPaise: i % 17 == 0 ? 1000 + i : -(1000 + i),
        at: DateTime(2026, 9, 1 + i % 30, 9, i % 60),
      ),
  ];
}

void main() {
  group('summariseAsync', () {
    test('a 5,000-row month comes back exactly as the synchronous path',
        () async {
      final rows = _rows(5000);
      expect(
        rows.length,
        greaterThan(isolateThresholdRows),
        reason: 'a month this size is folded in an isolate, not in place',
      );

      final viaIsolate =
          await summariseAsync(rows, _month, prevTotalPaise: 987654);
      final inPlace =
          Aggregator.summarise(rows, _month, prevTotalPaise: 987654);

      // Every integer, every key order and every zero-filled day.
      expect(viaIsolate, inPlace);
      expect(viaIsolate.totalPaise, inPlace.totalPaise);
      expect(viaIsolate.byCategory.keys.toList(),
          inPlace.byCategory.keys.toList());
      expect(viaIsolate.byDay, inPlace.byDay);
      expect(viaIsolate.byDay, hasLength(30));
      expect(viaIsolate.prevTotalPaise, 987654);
    });

    test('the day buckets survive the trip through JSON', () async {
      // A row at 00:30 local on the 1st and one at 23:30 on the 30th are the
      // ends of the month; an isolate that rebuilt them in UTC would push one
      // of them onto a day that is not in September at all.
      final rows = [
        ..._rows(2100),
        txn(
            id: 'txn_first',
            at: DateTime(2026, 9, 1, 0, 30),
            amountPaise: -500),
        txn(
            id: 'txn_last',
            at: DateTime(2026, 9, 30, 23, 30),
            amountPaise: -700),
      ];

      final summary = await summariseAsync(rows, _month);

      expect(summary, Aggregator.summarise(rows, _month));
      expect(summary.byDay.first.paise,
          Aggregator.summarise(rows, _month).byDay.first.paise);
      expect(summary.byDay.last.paise,
          Aggregator.summarise(rows, _month).byDay.last.paise);
    });

    test('a small month never leaves the main isolate, and agrees anyway',
        () async {
      final rows = _rows(isolateThresholdRows);

      expect(
        await summariseAsync(rows, _month, prevTotalPaise: 10),
        Aggregator.summarise(rows, _month, prevTotalPaise: 10),
      );
    });

    test('an empty month is zeros and a full set of days', () async {
      final summary = await summariseAsync(const <Transaction>[], _month);

      expect(summary,
          MonthSummary.empty.copyWith(month: _month, byDay: summary.byDay));
      expect(summary.totalPaise, 0);
      expect(summary.byCategory, isEmpty);
      expect(summary.byDay, hasLength(30));
    });
  });
}
