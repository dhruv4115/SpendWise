import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/transactions/state/day_groups.dart';

import '../helpers/transactions.dart';

void main() {
  group('groupByDay', () {
    test('an empty feed has no sections', () {
      expect(groupByDay(const []), isEmpty);
    });

    test('one section per local day, newest first, rows in feed order', () {
      final feed = [
        txn(id: 'a', at: DateTime(2026, 9, 23, 20)),
        txn(id: 'b', at: DateTime(2026, 9, 23, 9)),
        txn(id: 'c', at: DateTime(2026, 9, 22, 18)),
        txn(id: 'd', at: DateTime(2026, 9, 20, 7)),
        txn(id: 'e', at: DateTime(2026, 9, 20, 6)),
      ];

      final groups = groupByDay(feed);

      expect(groups.map((g) => g.day), [
        DateTime(2026, 9, 23),
        DateTime(2026, 9, 22),
        DateTime(2026, 9, 20),
      ]);
      expect(groups.map((g) => g.items.map((t) => t.id).toList()), [
        ['a', 'b'],
        ['c'],
        ['d', 'e'],
      ]);
    });

    test('splits at local midnight, not at the UTC date', () {
      // The model already holds local time; 23:59 and 00:01 are two days to
      // the customer however close they are in UTC.
      final groups = groupByDay([
        txn(id: 'late', at: DateTime(2026, 9, 13, 0, 1)),
        txn(id: 'early', at: DateTime(2026, 9, 12, 23, 59)),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.day, DateTime(2026, 9, 13));
      expect(groups.last.day, DateTime(2026, 9, 12));
    });

    test('the day total is the signed sum of its rows', () {
      final groups = groupByDay([
        txn(amountPaise: -45250, at: DateTime(2026, 9, 23, 20)),
        txn(amountPaise: -12000, at: DateTime(2026, 9, 23, 12)),
        txn(amountPaise: 5000, at: DateTime(2026, 9, 23, 10)),
      ]);

      expect(groups.single.totalPaise, -52250);
      expect(groups.single.spentPaise, 52250);
    });

    test('a day of nothing but refunds totals positive', () {
      final groups = groupByDay([
        txn(id: 'spend', amountPaise: -30000, at: DateTime(2026, 9, 23, 9)),
        txn(id: 'r1', amountPaise: 19900, at: DateTime(2026, 9, 22, 18)),
        txn(id: 'r2', amountPaise: 101, at: DateTime(2026, 9, 22, 11)),
      ]);

      final refunds = groups.last;
      expect(refunds.day, DateTime(2026, 9, 22));
      expect(refunds.items.map((t) => t.id), ['r1', 'r2']);
      expect(refunds.totalPaise, 20001);
      // Negative spend, and not floored: flooring is display-only.
      expect(refunds.spentPaise, -20001);
      // The spend day next to it is untouched by the refunds.
      expect(groups.first.totalPaise, -30000);
    });

    test('a day whose refunds outweigh its spends totals positive', () {
      final groups = groupByDay([
        txn(amountPaise: -1000, at: DateTime(2026, 9, 22, 18)),
        txn(amountPaise: 2500, at: DateTime(2026, 9, 22, 9)),
      ]);

      expect(groups.single.totalPaise, 1500);
    });

    test('sums exactly, with no floating-point drift', () {
      // 10,000 rows of -₹0.01 through -₹99.99 add to exactly this.
      final feed = [
        for (var i = 0; i < 10000; i++)
          txn(amountPaise: -(1 + i % 9999), at: DateTime(2026, 9, 22, 12)),
      ];
      var expected = 0;
      for (var i = 0; i < 10000; i++) {
        expected -= 1 + i % 9999;
      }

      expect(groupByDay(feed).single.totalPaise, expected);
    });

    test('a day that reappears later joins its first section', () {
      final groups = groupByDay([
        txn(id: 'a', at: DateTime(2026, 9, 23, 9)),
        txn(id: 'b', at: DateTime(2026, 9, 22, 9)),
        txn(id: 'c', at: DateTime(2026, 9, 23, 8)),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.items.map((t) => t.id), ['a', 'c']);
    });

    test('sections are unmodifiable', () {
      final groups = groupByDay([txn()]);

      expect(() => groups.single.items.add(txn()), throwsUnsupportedError);
    });
  });
}
