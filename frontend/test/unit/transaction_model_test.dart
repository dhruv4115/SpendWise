import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/budgets/domain/budget.dart';
import 'package:spendwise/features/categories/domain/category.dart';
import 'package:spendwise/features/merchants/domain/merchant_insight.dart';
import 'package:spendwise/features/merchants/domain/merchant_rule.dart';
import 'package:spendwise/features/overview/domain/insight_card.dart';
import 'package:spendwise/features/overview/domain/month_summary.dart';
import 'package:spendwise/features/transactions/domain/transaction.dart';
import 'package:spendwise/features/transactions/domain/transaction_filter.dart';

/// Exactly what `GET /transactions/{id}` sends.
Map<String, dynamic> txnJson({
  String id = 'txn_202609_0040',
  String merchantRaw = 'SWIGGY*1234',
  String merchantName = 'Swiggy',
  String merchantKey = 'swiggy',
  String category = 'food',
  int amountPaise = -45250,
  String at = '2026-09-12T18:30:00.000Z',
  String mode = 'UPI',
}) {
  return {
    'id': id,
    'merchantRaw': merchantRaw,
    'merchantName': merchantName,
    'merchantKey': merchantKey,
    'category': category,
    'amountPaise': amountPaise,
    'at': at,
    'mode': mode,
  };
}

void main() {
  group('Transaction.fromJson', () {
    test('reads every field off the wire', () {
      final txn = Transaction.fromJson(txnJson());

      expect(txn.id, 'txn_202609_0040');
      expect(txn.merchantRaw, 'SWIGGY*1234');
      expect(txn.merchantName, 'Swiggy');
      expect(txn.merchantKey, 'swiggy');
      expect(txn.category, 'food');
      expect(txn.amountPaise, -45250);
      expect(txn.mode, 'UPI');
    });

    test('converts the UTC timestamp to local time, exactly once', () {
      final txn = Transaction.fromJson(
        txnJson(at: '2026-09-12T18:30:00.000Z'),
      );

      expect(txn.at.isUtc, isFalse, reason: 'models store local time');
      expect(
        txn.at.toUtc(),
        DateTime.utc(2026, 9, 12, 18, 30),
        reason: 'the instant must survive the conversion',
      );
      // The local calendar fields are the device's, whatever zone it is in.
      final expected = DateTime.utc(2026, 9, 12, 18, 30).toLocal();
      expect(txn.at, expected);
    });

    test('reads a timestamp with an offset as the instant it names', () {
      final txn = Transaction.fromJson(
        txnJson(at: '2026-09-12T18:30:00.000+05:30'),
      );

      expect(txn.at.toUtc(), DateTime.utc(2026, 9, 12, 13, 0));
    });

    test('a zoneless timestamp is read as UTC, not as local', () {
      final txn = Transaction.fromJson(txnJson(at: '2026-09-12T18:30:00.000'));

      expect(txn.at.toUtc(), DateTime.utc(2026, 9, 12, 18, 30));
    });

    test('round-trips through toJson', () {
      final original = Transaction.fromJson(txnJson());

      final restored = Transaction.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
      expect(restored.at, original.at);
    });

    test('keeps the sign convention: a debit is negative', () {
      final debit = Transaction.fromJson(txnJson(amountPaise: -45250));
      final refund = Transaction.fromJson(txnJson(amountPaise: 45250));

      expect(debit.isRefund, isFalse);
      expect(debit.spentPaise, 45250, reason: 'spend is the flipped sign');
      expect(refund.isRefund, isTrue);
      expect(refund.spentPaise, -45250, reason: 'a refund is negative spend');
    });

    group('throws FormatException on a malformed payload', () {
      test('when a field is missing', () {
        final json = txnJson()..remove('merchantKey');

        expect(
          () => Transaction.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('merchantKey'),
            ),
          ),
        );
      });

      test('when a field is the wrong type', () {
        final json = txnJson()..['id'] = 42;

        expect(() => Transaction.fromJson(json), throwsFormatException);
      });

      test('when a string field is empty', () {
        final json = txnJson()..['category'] = '';

        expect(() => Transaction.fromJson(json), throwsFormatException);
      });

      test('when the amount is fractional rather than whole paise', () {
        final json = txnJson()..['amountPaise'] = -452.5;

        expect(
          () => Transaction.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('amountPaise'),
            ),
          ),
        );
      });

      test('when the timestamp is not a timestamp', () {
        final json = txnJson()..['at'] = 'last Tuesday';

        expect(() => Transaction.fromJson(json), throwsFormatException);
      });

      test('when the timestamp is not a string', () {
        final json = txnJson()..['at'] = 1789012345;

        expect(() => Transaction.fromJson(json), throwsFormatException);
      });
    });

    test('equality is by value, and copyWith changes one field', () {
      final txn = Transaction.fromJson(txnJson());

      expect(txn, Transaction.fromJson(txnJson()));
      expect(txn.hashCode, Transaction.fromJson(txnJson()).hashCode);
      expect(txn, isNot(txn.copyWith(category: 'groceries')));
      expect(txn.copyWith(category: 'groceries').amountPaise, txn.amountPaise);
      expect(txn.copyWith(), txn);
    });

    test('toString carries no amount and no merchant', () {
      final txn = Transaction.fromJson(txnJson());

      expect(txn.toString(), isNot(contains('45250')));
      expect(txn.toString(), isNot(contains('Swiggy')));
      expect(txn.toString(), isNot(contains('txn_202609_0040')));
      expect(txn.toString(), contains('food'));
    });
  });

  group('Category', () {
    Map<String, dynamic> json() => {
          'id': 'food',
          'name': 'Food & Dining',
          'icon': 'restaurant',
          'color': '#E8590C',
        };

    test('parses and exposes the colour as opaque ARGB', () {
      final category = Category.fromJson(json());

      expect(category.id, 'food');
      expect(category.name, 'Food & Dining');
      expect(category.icon, 'restaurant');
      expect(category.argb, 0xFFE8590C);
    });

    test('rejects a colour that is not #RRGGBB', () {
      expect(
        () => Category.fromJson(json()..['color'] = 'orange'),
        throwsFormatException,
      );
      expect(
        () => Category.fromJson(json()..['color'] = '#FFF'),
        throwsFormatException,
      );
    });

    test('is a value', () {
      expect(Category.fromJson(json()), Category.fromJson(json()));
      expect(
        Category.fromJson(json()).hashCode,
        Category.fromJson(json()).hashCode,
      );
      expect(
        Category.fromJson(json()),
        isNot(Category.fromJson(json()).copyWith(name: 'Eating out')),
      );
      expect(Category.fromJson(json()).copyWith(), Category.fromJson(json()));
      expect(Category.fromJson(json()).toString(), 'Category(food)');
    });
  });

  group('Budget', () {
    Map<String, dynamic> json() => {
          'category': 'food',
          'month': '2026-09',
          'limitPaise': 1000000,
          'spentPaise': 860000,
        };

    test('parses and derives what is left', () {
      final budget = Budget.fromJson(json());

      expect(budget.remainingPaise, 140000);
      expect(budget.isOverLimit, isFalse);
      expect(budget.usedPercent, 86);
    });

    test('a fresh budget arrives without a spend', () {
      final budget = Budget.fromJson(json()..remove('spentPaise'));

      expect(budget.spentPaise, 0);
      expect(budget.usedPercent, 0);
    });

    test('reports a breach, and percentages pass 100', () {
      final budget = Budget.fromJson(json()..['spentPaise'] = 1250000);

      expect(budget.isOverLimit, isTrue);
      expect(budget.remainingPaise, -250000);
      expect(budget.usedPercent, 125);
    });

    test('a zero limit never divides by zero', () {
      final budget = Budget.fromJson(json()..['limitPaise'] = 0);

      expect(budget.usedPercent, 0);
      expect(budget.isOverLimit, isTrue);
    });

    test('a net-refund month is negative, not floored', () {
      final budget = Budget.fromJson(json()..['spentPaise'] = -5000);

      expect(budget.spentPaise, -5000);
      expect(budget.usedPercent, 0);
      expect(budget.remainingPaise, 1005000);
    });

    test('is a value', () {
      expect(Budget.fromJson(json()), Budget.fromJson(json()));
      expect(
          Budget.fromJson(json()).hashCode, Budget.fromJson(json()).hashCode);
      expect(
        Budget.fromJson(json()).copyWith(limitPaise: 1),
        isNot(Budget.fromJson(json())),
      );
      expect(Budget.fromJson(json()).copyWith(), Budget.fromJson(json()));
      expect(Budget.fromJson(json()).toString(), 'Budget(food, 2026-09)');
    });
  });

  group('MerchantInsight and MerchantRule', () {
    test('MerchantInsight parses and round-trips', () {
      final json = {
        'merchantKey': 'swiggy',
        'merchantName': 'Swiggy',
        'totalPaise': 450000,
        'visits': 12,
        'avgPaise': 37500,
        'topCategory': 'food',
      };

      final insight = MerchantInsight.fromJson(json);

      expect(insight.visits, 12);
      expect(insight.avgPaise, 37500);
      expect(MerchantInsight.fromJson(insight.toJson()), insight);
      expect(
        MerchantInsight.fromJson(json).hashCode,
        MerchantInsight.fromJson(json).hashCode,
      );
      expect(insight.copyWith(visits: 13), isNot(insight));
      expect(insight.copyWith(), insight);
      expect(insight.toString(), contains('swiggy'));
    });

    test('MerchantRule is a value', () {
      const json = {'merchantKey': 'swiggy', 'category': 'food'};

      final rule = MerchantRule.fromJson(json);

      expect(rule.merchantKey, 'swiggy');
      expect(rule, MerchantRule.fromJson(json));
      expect(rule.hashCode, MerchantRule.fromJson(json).hashCode);
      expect(rule.copyWith(category: 'groceries').category, 'groceries');
      expect(rule.copyWith(), rule);
      expect(rule.toString(), contains('swiggy'));
      expect(
        () => MerchantRule.fromJson(const {'merchantKey': 'swiggy'}),
        throwsFormatException,
      );
    });
  });

  group('MonthSummary', () {
    Map<String, dynamic> json() => {
          'month': '2026-09',
          'totalPaise': 500000,
          'prevTotalPaise': 400000,
          'byCategory': {'food': 300000, 'transport': 200000},
          'byDay': [
            {'date': '2026-09-01', 'paise': 200000},
            {'date': '2026-09-02', 'paise': 300000},
          ],
        };

    test('parses nested days and categories', () {
      final summary = MonthSummary.fromJson(json());

      expect(summary.byCategory['food'], 300000);
      expect(summary.byDay, hasLength(2));
      expect(summary.byDay.first.date, DateTime(2026, 9, 1));
      expect(summary.byDay.first.date.isUtc, isFalse);
      expect(summary.deltaPaise, 100000);
      expect(summary.deltaPercent, 25);
      expect(summary.isEmpty, isFalse);
    });

    test('has no percentage to report without a previous month', () {
      final summary = MonthSummary.fromJson(json()..['prevTotalPaise'] = 0);

      expect(summary.deltaPercent, isNull);
      expect(summary.deltaPaise, 500000);
    });

    test('round-trips through JSON with deep equality', () {
      final summary = MonthSummary.fromJson(json());

      final restored = MonthSummary.fromJson(
        jsonDecode(jsonEncode(summary.toJson())) as Map<String, dynamic>,
      );

      expect(restored, summary);
      expect(restored.hashCode, summary.hashCode);
      expect(summary.copyWith(), summary);
    });

    test('differs when a single day differs', () {
      final summary = MonthSummary.fromJson(json());
      final other = MonthSummary.fromJson(
        json()
          ..['byDay'] = [
            {'date': '2026-09-01', 'paise': 200000},
            {'date': '2026-09-02', 'paise': 1},
          ],
      );

      expect(other, isNot(summary));
    });

    test('the empty summary is empty', () {
      expect(MonthSummary.empty.isEmpty, isTrue);
      expect(MonthSummary.empty.byDay, isEmpty);
      expect(MonthSummary.empty.copyWith(month: '2026-09').month, '2026-09');
      expect(MonthSummary.empty.toString(), contains('days: 0'));
    });

    test('rejects a day whose date is not a date', () {
      expect(
        () => MonthSummary.fromJson(
          json()
            ..['byDay'] = [
              {'date': '12 September', 'paise': 1},
            ],
        ),
        throwsFormatException,
      );
    });

    test('rejects a date that is well formed but not real', () {
      // DateTime.parse would quietly read these as January 2027 and 3 March.
      for (final date in ['2026-13-01', '2026-02-31', '2026-00-10']) {
        expect(
          () => MonthSummary.fromJson(
            json()
              ..['byDay'] = [
                {'date': date, 'paise': 1},
              ],
          ),
          throwsFormatException,
          reason: '$date is not a day',
        );
      }
    });

    test('rejects a previous-month total that is not a number', () {
      expect(
        () => MonthSummary.fromJson(json()..['prevTotalPaise'] = '400000'),
        throwsFormatException,
      );
    });

    test('rejects a category total that is not a whole number', () {
      expect(
        () => MonthSummary.fromJson(json()..['byCategory'] = {'food': 1.5}),
        throwsFormatException,
      );
    });

    test('rejects byDay entries that are not objects', () {
      expect(
        () => MonthSummary.fromJson(json()..['byDay'] = ['2026-09-01']),
        throwsFormatException,
      );
    });

    test('DailyTotal is a value and prints its date', () {
      final day = DailyTotal(date: DateTime(2026, 9, 1), paise: 100);

      expect(day.copyWith(paise: 200).paise, 200);
      expect(day.copyWith().date, DateTime(2026, 9, 1));
      expect(day.toString(), contains('2026-09-01'));
      expect(day, DailyTotal(date: DateTime(2026, 9, 1), paise: 100));
      expect(day.hashCode,
          DailyTotal(date: DateTime(2026, 9, 1), paise: 100).hashCode);
      expect(day, isNot(DailyTotal(date: DateTime(2026, 9, 2), paise: 100)));
    });
  });

  group('InsightCard', () {
    Map<String, dynamic> json() => {
          'id': 'budget_2026-09',
          'title': 'Food & Dining is over budget',
          'body': 'You have spent ₹12,500 against a ₹10,000 limit.',
          'severity': 'critical',
          'dismissible': false,
        };

    test('parses severity and dismissibility', () {
      final card = InsightCard.fromJson(json());

      expect(card.severity, InsightSeverity.critical);
      expect(card.dismissible, isFalse);
    });

    test('an unknown severity degrades to info rather than throwing', () {
      final card = InsightCard.fromJson(json()..['severity'] = 'apocalyptic');

      expect(card.severity, InsightSeverity.info);
    });

    test('defaults to dismissible when the server says nothing', () {
      final card = InsightCard.fromJson(json()..remove('dismissible'));

      expect(card.dismissible, isTrue);
    });

    test('rejects a dismissible flag that is not a boolean', () {
      expect(
        () => InsightCard.fromJson(json()..['dismissible'] = 'yes'),
        throwsFormatException,
      );
    });

    test('is a value', () {
      expect(InsightCard.fromJson(json()), InsightCard.fromJson(json()));
      expect(
        InsightCard.fromJson(json()).hashCode,
        InsightCard.fromJson(json()).hashCode,
      );
      expect(
        InsightCard.fromJson(json()).copyWith(title: 'Other'),
        isNot(InsightCard.fromJson(json())),
      );
      expect(
        InsightCard.fromJson(json()).copyWith(),
        InsightCard.fromJson(json()),
      );
      expect(InsightCard.fromJson(json()).toString(), contains('critical'));
    });
  });

  group('TransactionFilter', () {
    test('an empty filter is inactive and sends nothing', () {
      expect(TransactionFilter.none.isActive, isFalse);
      expect(TransactionFilter.none.activeCount, 0);
      expect(TransactionFilter.none.toQueryParameters(), isEmpty);
    });

    test('whitespace is not a search', () {
      const filter = TransactionFilter(query: '   ');

      expect(filter.isActive, isFalse);
      expect(filter.toQueryParameters(), isEmpty);
    });

    test('serialises only the fields that are set', () {
      final filter = TransactionFilter(
        category: 'food',
        query: '  swiggy  ',
        minPaise: 50000,
        from: DateTime.utc(2026, 9, 1),
      );

      expect(filter.toQueryParameters(), {
        'category': 'food',
        'q': 'swiggy',
        'minPaise': '50000',
        'from': '2026-09-01T00:00:00.000Z',
      });
      expect(filter.activeCount, 4);
      expect(filter.isActive, isTrue);
    });

    test('dates go out as UTC whatever zone they were picked in', () {
      final local = DateTime.utc(2026, 9, 30, 18, 30).toLocal();
      final filter = TransactionFilter(to: local);

      expect(
        filter.toQueryParameters()['to'],
        '2026-09-30T18:30:00.000Z',
      );
    });

    test('equal filters are equal, so a provider family dedupes', () {
      final a = TransactionFilter(
        category: 'food',
        query: 'swiggy',
        minPaise: 1,
        maxPaise: 2,
        from: DateTime.utc(2026, 9, 1),
        to: DateTime.utc(2026, 9, 30),
      );
      final b = TransactionFilter(
        category: 'food',
        query: 'swiggy',
        minPaise: 1,
        maxPaise: 2,
        from: DateTime.utc(2026, 9, 1),
        to: DateTime.utc(2026, 9, 30),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('the same instant in a different zone is the same filter', () {
      final utc = TransactionFilter(from: DateTime.utc(2026, 9, 1, 12));
      final local = TransactionFilter(
        from: DateTime.utc(2026, 9, 1, 12).toLocal(),
      );

      expect(local, utc, reason: 'DateTime.== would disagree on isUtc');
      expect(local.hashCode, utc.hashCode);
    });

    test('differing filters are not equal', () {
      const base = TransactionFilter(category: 'food');

      expect(base, isNot(const TransactionFilter(category: 'transport')));
      expect(base, isNot(const TransactionFilter()));
      expect(
        const TransactionFilter(minPaise: 1),
        isNot(const TransactionFilter(maxPaise: 1)),
      );
      expect(
        TransactionFilter(to: DateTime.utc(2026)),
        isNot(TransactionFilter(to: DateTime.utc(2027))),
      );
    });

    test('copyWith sets, keeps and clears', () {
      final filter = TransactionFilter(
        category: 'food',
        query: 'swiggy',
        minPaise: 100,
        maxPaise: 900,
        from: DateTime.utc(2026, 9, 1),
        to: DateTime.utc(2026, 9, 30),
      );

      // Set.
      expect(filter.copyWith(category: 'travel').category, 'travel');
      // Keep: an omitted field survives.
      expect(filter.copyWith(query: 'zomato').category, 'food');
      expect(filter.copyWith(query: 'zomato').minPaise, 100);
      // Clear.
      expect(filter.copyWith(category: null).category, isNull);
      expect(filter.copyWith(minPaise: null).minPaise, isNull);
      expect(filter.copyWith(maxPaise: null).maxPaise, isNull);
      expect(filter.copyWith(from: null).from, isNull);
      expect(filter.copyWith(to: null).to, isNull);
      // Clearing one leaves the rest alone.
      expect(filter.copyWith(from: null).to, filter.to);
    });

    test('cleared() goes back to nothing', () {
      const filter = TransactionFilter(category: 'food', query: 'x');

      expect(filter.cleared(), TransactionFilter.none);
      expect(filter.toString(), contains('2'));
    });
  });
}
