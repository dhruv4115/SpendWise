import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/overview/data/aggregator.dart';
import 'package:spendwise/features/overview/data/summarise_async.dart';
import 'package:spendwise/features/overview/domain/month_summary.dart';
import 'package:spendwise/features/transactions/domain/transaction.dart';

/// Builds a transaction directly, in local time.
///
/// Deliberately not via `fromJson`: these tests are about arithmetic and day
/// bucketing, and a wire timestamp would make every expectation depend on the
/// machine's time zone.
Transaction txn({
  String id = 'txn_1',
  String category = 'food',
  int amountPaise = -100000,
  DateTime? at,
  String merchantKey = 'swiggy',
  String merchantName = 'Swiggy',
  String merchantRaw = 'SWIGGY*1234',
  String mode = 'UPI',
}) {
  return Transaction(
    id: id,
    merchantRaw: merchantRaw,
    merchantName: merchantName,
    merchantKey: merchantKey,
    category: category,
    amountPaise: amountPaise,
    at: at ?? DateTime(2026, 9, 12, 18, 30),
    mode: mode,
  );
}

/// The day totals that are not zero, as `'YYYY-MM-DD': paise`.
Map<String, int> nonZeroDays(List<DailyTotal> days) => {
      for (final day in days)
        if (day.paise != 0)
          '${day.date.year}-${day.date.month.toString().padLeft(2, '0')}-'
              '${day.date.day.toString().padLeft(2, '0')}': day.paise,
    };

void main() {
  group('byCategory', () {
    test('sums each category exactly, to the paise', () {
      final totals = Aggregator.byCategory([
        txn(category: 'food', amountPaise: -45250),
        txn(category: 'food', amountPaise: -1),
        txn(category: 'transport', amountPaise: -33333),
        txn(category: 'food', amountPaise: -999999999),
      ]);

      expect(totals['food'], 45250 + 1 + 999999999);
      expect(totals['transport'], 33333);
    });

    test('a refund reduces its own category', () {
      final totals = Aggregator.byCategory([
        txn(category: 'food', amountPaise: -50000),
        txn(category: 'food', amountPaise: 20000), // refund
        txn(category: 'travel', amountPaise: -10000),
      ]);

      expect(totals['food'], 30000);
      expect(totals['travel'], 10000);
    });

    test('a category refunded more than it was spent goes negative', () {
      final totals = Aggregator.byCategory([
        txn(category: 'shopping', amountPaise: -10000),
        txn(category: 'shopping', amountPaise: 25000),
      ]);

      expect(totals['shopping'], -15000, reason: 'not floored at zero');
    });

    test('orders by spend, largest first', () {
      final totals = Aggregator.byCategory([
        txn(category: 'food', amountPaise: -20000),
        txn(category: 'travel', amountPaise: -90000),
        txn(category: 'bills', amountPaise: -50000),
      ]);

      expect(totals.keys.toList(), ['travel', 'bills', 'food']);
    });

    test('breaks ties on the category id, so the order is stable', () {
      final totals = Aggregator.byCategory([
        txn(category: 'transport', amountPaise: -20000),
        txn(category: 'food', amountPaise: -20000),
        txn(category: 'bills', amountPaise: -20000),
      ]);

      expect(totals.keys.toList(), ['bills', 'food', 'transport']);
    });

    test('an empty month has no categories', () {
      expect(Aggregator.byCategory([]), isEmpty);
    });
  });

  group('byDay', () {
    test('covers every day of a 30-day month, zero-filled and ascending', () {
      final days = Aggregator.byDay([
        txn(at: DateTime(2026, 9, 1, 9), amountPaise: -1000),
        txn(at: DateTime(2026, 9, 30, 23, 59), amountPaise: -2000),
      ], '2026-09');

      expect(days, hasLength(30));
      expect(days.first.date, DateTime(2026, 9, 1));
      expect(days.last.date, DateTime(2026, 9, 30));
      expect(days[0].paise, 1000);
      expect(days[29].paise, 2000);
      // Every day between them is present and zero.
      expect(days.sublist(1, 29).every((day) => day.paise == 0), isTrue);
      expect(
        days.map((day) => day.date.day).toList(),
        List<int>.generate(30, (index) => index + 1),
      );
    });

    test('covers all 31 days of a 31-day month', () {
      final days = Aggregator.byDay([], '2026-01');

      expect(days, hasLength(31));
      expect(days.last.date, DateTime(2026, 1, 31));
    });

    test('a common February has 28 days', () {
      final days = Aggregator.byDay([], '2026-02');

      expect(days, hasLength(28));
      expect(days.last.date, DateTime(2026, 2, 28));
    });

    test('a leap February has 29 days', () {
      final days = Aggregator.byDay([], '2024-02');

      expect(days, hasLength(29));
      expect(days.last.date, DateTime(2024, 2, 29));
    });

    test('a century year divisible by 400 is still a leap year', () {
      expect(Aggregator.byDay([], '2000-02'), hasLength(29));
      expect(Aggregator.byDay([], '1900-02'), hasLength(28));
    });

    test('several transactions on one day are added together', () {
      final days = Aggregator.byDay([
        txn(at: DateTime(2026, 9, 12, 8), amountPaise: -30000),
        txn(at: DateTime(2026, 9, 12, 21), amountPaise: -12345),
        txn(at: DateTime(2026, 9, 12, 22), amountPaise: 2345), // refund
      ], '2026-09');

      expect(nonZeroDays(days), {'2026-09-12': 40000});
    });

    test('a day whose refunds outweigh its spends is negative', () {
      final days = Aggregator.byDay([
        txn(at: DateTime(2026, 9, 3), amountPaise: -1000),
        txn(at: DateTime(2026, 9, 3), amountPaise: 4000),
      ], '2026-09');

      expect(nonZeroDays(days), {'2026-09-03': -3000});
    });

    test('a local date outside the month gets no bar', () {
      // A payment that lands on 1 October once converted to local time.
      final days = Aggregator.byDay([
        txn(at: DateTime(2026, 10, 1, 0, 30), amountPaise: -5000),
        txn(at: DateTime(2026, 9, 15), amountPaise: -1000),
      ], '2026-09');

      expect(days, hasLength(30));
      expect(nonZeroDays(days), {'2026-09-15': 1000});
    });

    test('rejects a month that is not YYYY-MM', () {
      expect(() => Aggregator.byDay([], 'September'), throwsFormatException);
      expect(() => Aggregator.byDay([], '2026-13'), throwsFormatException);
    });
  });

  group('summarise', () {
    test('an empty month is zeroed, with a full zero-filled byDay', () {
      final summary = Aggregator.summarise([], '2026-02');

      expect(summary.month, '2026-02');
      expect(summary.totalPaise, 0);
      expect(summary.prevTotalPaise, 0);
      expect(summary.byCategory, isEmpty);
      expect(summary.byDay, hasLength(28));
      expect(summary.byDay.every((day) => day.paise == 0), isTrue);
      expect(summary.isEmpty, isTrue);
    });

    test('totals, categories and days agree with each other', () {
      final summary = Aggregator.summarise(
        [
          txn(category: 'food', amountPaise: -45250, at: DateTime(2026, 9, 1)),
          txn(
            category: 'transport',
            amountPaise: -12000,
            at: DateTime(2026, 9, 1),
          ),
          txn(category: 'food', amountPaise: -30000, at: DateTime(2026, 9, 2)),
        ],
        '2026-09',
        prevTotalPaise: 100000,
      );

      expect(summary.totalPaise, 87250);
      expect(summary.byCategory, {'food': 75250, 'transport': 12000});
      expect(nonZeroDays(summary.byDay), {
        '2026-09-01': 57250,
        '2026-09-02': 30000,
      });
      expect(
        summary.byDay.fold<int>(0, (sum, day) => sum + day.paise),
        summary.totalPaise,
      );
      expect(summary.prevTotalPaise, 100000);
      expect(summary.deltaPaise, -12750);
    });

    test('a refund reduces the month total as well as its category', () {
      final withoutRefund = Aggregator.summarise([
        txn(category: 'shopping', amountPaise: -80000),
      ], '2026-09');

      final withRefund = Aggregator.summarise([
        txn(category: 'shopping', amountPaise: -80000),
        txn(category: 'shopping', amountPaise: 30000),
      ], '2026-09');

      expect(withoutRefund.totalPaise, 80000);
      expect(withRefund.totalPaise, 50000);
      expect(withRefund.byCategory['shopping'], 50000);
    });

    test('a month of nothing but refunds is negative', () {
      final summary = Aggregator.summarise([
        txn(amountPaise: 45000),
      ], '2026-09');

      expect(summary.totalPaise, -45000);
    });

    test('adds up 5,200 rows without losing a paisa', () {
      // The stress month in the seed data. Every amount is odd, so any
      // floating-point step would show up in the last digit.
      final txns = [
        for (var index = 0; index < 5200; index++)
          txn(
            id: 'txn_$index',
            amountPaise: -(999983 + index * 7),
            at: DateTime(2026, 9, 1 + index % 30),
          ),
      ];

      var expected = 0;
      for (var index = 0; index < 5200; index++) {
        expected += 999983 + index * 7;
      }

      final summary = Aggregator.summarise(txns, '2026-09');

      expect(summary.totalPaise, expected);
      expect(summary.byCategory['food'], expected);
      expect(
        summary.byDay.fold<int>(0, (sum, day) => sum + day.paise),
        expected,
      );
    });
  });

  group('normaliseMerchant', () {
    test('maps every card-network spelling of one merchant to one key', () {
      expect(Aggregator.normaliseMerchant('SWIGGY*1234'), 'swiggy');
      expect(Aggregator.normaliseMerchant('SWIGGY *8891'), 'swiggy');
      expect(Aggregator.normaliseMerchant('swiggy-2201'), 'swiggy');
    });

    test('keeps the space inside a two-word merchant', () {
      expect(Aggregator.normaliseMerchant('BIG BASKET*9912'), 'big basket');
      expect(Aggregator.normaliseMerchant('BIG BASKET *4420'), 'big basket');
      expect(Aggregator.normaliseMerchant('big basket-118'), 'big basket');
    });

    test('collapses whatever whitespace the noise leaves behind', () {
      expect(Aggregator.normaliseMerchant('  UBER   *  3391  '), 'uber');
      expect(Aggregator.normaliseMerchant('UBER\t*\n7781'), 'uber');
    });

    test('a descriptor of nothing but noise normalises to empty', () {
      expect(Aggregator.normaliseMerchant('*-1234'), '');
      expect(Aggregator.normaliseMerchant(''), '');
    });

    test('matches the keys the backend seeds', () {
      // Sampled from backend/src/data/seed.js — if either rule drifts, a
      // locally grouped merchant would stop matching a fetched one.
      expect(Aggregator.normaliseMerchant('ZOMATO*4410'), 'zomato');
      expect(Aggregator.normaliseMerchant('zomato-7781'), 'zomato');
      expect(Aggregator.normaliseMerchant('AMAZON *1180'), 'amazon');
      expect(Aggregator.normaliseMerchant('CAFE COFFEE DAY*4102'),
          'cafe coffee day');
    });
  });

  group('merchantInsights', () {
    test('sorts by total spend, largest first', () {
      final insights = Aggregator.merchantInsights([
        txn(merchantKey: 'swiggy', merchantName: 'Swiggy', amountPaise: -20000),
        txn(merchantKey: 'uber', merchantName: 'Uber', amountPaise: -90000),
        txn(merchantKey: 'zepto', merchantName: 'Zepto', amountPaise: -50000),
      ]);

      expect(
        insights.map((insight) => insight.merchantKey).toList(),
        ['uber', 'zepto', 'swiggy'],
      );
      expect(insights.first.totalPaise, 90000);
    });

    test('breaks a tie on the merchant key, matching the server', () {
      final insights = Aggregator.merchantInsights([
        txn(merchantKey: 'zepto', merchantName: 'Zepto', amountPaise: -10000),
        txn(merchantKey: 'amazon', merchantName: 'Amazon', amountPaise: -10000),
        txn(merchantKey: 'myntra', merchantName: 'Myntra', amountPaise: -10000),
      ]);

      expect(
        insights.map((insight) => insight.merchantKey).toList(),
        ['amazon', 'myntra', 'zepto'],
      );
    });

    test('counts visits and averages with integer division', () {
      final insights = Aggregator.merchantInsights([
        txn(amountPaise: -1000),
        txn(amountPaise: -1000),
        txn(amountPaise: -1000),
        txn(amountPaise: -1), // 3001 over 4 visits
      ]);

      expect(insights.single.visits, 4);
      expect(insights.single.totalPaise, 3001);
      expect(insights.single.avgPaise, 750, reason: '3001 ~/ 4, truncated');
    });

    test('an average truncates towards zero for a refunded merchant', () {
      final insights = Aggregator.merchantInsights([
        txn(amountPaise: -1000),
        txn(amountPaise: 3001),
      ]);

      expect(insights.single.totalPaise, -2001);
      expect(insights.single.avgPaise, -1000, reason: '-2001 ~/ 2');
    });

    test('a refund counts as a visit and reduces the total', () {
      final insights = Aggregator.merchantInsights([
        txn(amountPaise: -50000),
        txn(amountPaise: 20000),
      ]);

      expect(insights.single.visits, 2);
      expect(insights.single.totalPaise, 30000);
    });

    test('groups every raw variant under the one key', () {
      final insights = Aggregator.merchantInsights([
        txn(merchantRaw: 'SWIGGY*1234', amountPaise: -10000),
        txn(merchantRaw: 'SWIGGY *8891', amountPaise: -20000),
        txn(merchantRaw: 'swiggy-2201', amountPaise: -30000),
      ]);

      expect(insights, hasLength(1));
      expect(insights.single.merchantKey, 'swiggy');
      expect(insights.single.visits, 3);
      expect(insights.single.totalPaise, 60000);
    });

    test('reports the category the merchant took the most in', () {
      final insights = Aggregator.merchantInsights([
        txn(category: 'food', amountPaise: -10000),
        txn(category: 'groceries', amountPaise: -40000),
        txn(category: 'food', amountPaise: -20000),
      ]);

      expect(insights.single.topCategory, 'groceries');
    });

    test('a tied top category falls back to the category id', () {
      final insights = Aggregator.merchantInsights([
        txn(category: 'groceries', amountPaise: -10000),
        txn(category: 'food', amountPaise: -10000),
      ]);

      expect(insights.single.topCategory, 'food');
    });

    test('uses the most recent spelling of the merchant name', () {
      final insights = Aggregator.merchantInsights([
        txn(merchantName: 'Twitter', at: DateTime(2026, 9, 1)),
        txn(merchantName: 'X', at: DateTime(2026, 9, 20)),
        txn(merchantName: 'Twitter', at: DateTime(2026, 9, 10)),
      ]);

      expect(insights.single.merchantName, 'X');
    });

    test('an empty month has no merchants', () {
      expect(Aggregator.merchantInsights([]), isEmpty);
    });
  });

  group('summariseAsync', () {
    test('matches the synchronous path below the threshold', () async {
      final txns = [
        for (var index = 0; index < isolateThresholdRows; index++)
          txn(
            id: 'txn_$index',
            amountPaise: -(1000 + index),
            at: DateTime(2026, 9, 1 + index % 30),
          ),
      ];

      final summary =
          await summariseAsync(txns, '2026-09', prevTotalPaise: 12345);

      expect(
        summary,
        Aggregator.summarise(txns, '2026-09', prevTotalPaise: 12345),
      );
    });

    test('goes through an isolate above the threshold, with the same answer',
        () async {
      final txns = [
        for (var index = 0; index <= isolateThresholdRows; index++)
          txn(
            id: 'txn_$index',
            category: index.isEven ? 'food' : 'travel',
            amountPaise: -(1000 + index),
            at: DateTime(2026, 9, 1 + index % 30),
          ),
      ];
      expect(txns, hasLength(greaterThan(isolateThresholdRows)));

      final summary = await summariseAsync(txns, '2026-09');

      expect(summary, Aggregator.summarise(txns, '2026-09'));
    });

    test('the isolate entry point is a pure JSON-to-JSON function', () {
      final payload = <String, Object?>{
        'month': '2026-09',
        'prevTotalPaise': 500,
        'items': [
          txn(amountPaise: -1000, at: DateTime(2026, 9, 4)).toJson(),
        ],
      };

      final summary = MonthSummary.fromJson(summariseIsolateEntry(payload));

      expect(summary.month, '2026-09');
      expect(summary.totalPaise, 1000);
      expect(summary.prevTotalPaise, 500);
      expect(nonZeroDays(summary.byDay), {'2026-09-04': 1000});
    });
  });
}
