import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/merchants/domain/merchant_insight.dart';
import 'package:spendwise/features/merchants/state/merchants_provider.dart';

import '../helpers/container.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/merchants.dart';

const String _month = '2026-09';

/// Four merchants whose three orders are all different, so no assertion here
/// can pass by accident:
///
/// | merchant  |   total |  visits | average |
/// |-----------|---------|---------|---------|
/// | Swiggy    | ₹9,000  |      12 |    ₹750 |
/// | Big Basket| ₹6,000  |       3 |  ₹2,000 |
/// | Uber      | ₹2,400  |       8 |    ₹300 |
/// | Croma     | ₹4,500  |       1 |  ₹4,500 |
final List<Map<String, Object?>> _four = [
  merchantWire(merchantName: 'Swiggy', totalPaise: 900000, visits: 12),
  merchantWire(
    merchantName: 'Big Basket',
    merchantKey: 'big basket',
    totalPaise: 600000,
    visits: 3,
    topCategory: 'groceries',
  ),
  merchantWire(
    merchantName: 'Uber',
    totalPaise: 240000,
    visits: 8,
    topCategory: 'transport',
  ),
  merchantWire(
    merchantName: 'Croma',
    totalPaise: 450000,
    visits: 1,
    topCategory: 'shopping',
  ),
];

ProviderContainer _container(FakeApi api) {
  return makeContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(
        FakeSessionStore(session: testSession),
      ),
      httpClientAdapterProvider.overrideWithValue(api),
    ],
  );
}

FakeApi _api([List<Map<String, Object?>>? items]) =>
    FakeApi()..on('GET', '/merchants', body: merchantsWire(items ?? _four));

/// The merchants in the order the screen would draw them.
Future<List<String>> _order(ProviderContainer container) async {
  await container.read(merchantsProvider(_month).future);
  final sorted = container.read(sortedMerchantsProvider(_month));
  return [for (final insight in sorted.requireValue) insight.merchantKey];
}

void main() {
  group('merchantsProvider', () {
    test('asks for the month it was keyed with, once', () async {
      final api = _api();
      final container = _container(api);
      readAndKeepAlive(container, merchantsProvider(_month));

      final merchants = await container.read(merchantsProvider(_month).future);

      expect(merchants, hasLength(4));
      expect(api.requestsFor('GET', '/merchants'), hasLength(1));
      expect(api.requestsFor('GET', '/merchants').single.query, {
        'month': _month,
      });
    });

    test('the rows carry the figures the server sent', () async {
      final container = _container(_api());
      readAndKeepAlive(container, merchantsProvider(_month));

      final merchants = await container.read(merchantsProvider(_month).future);
      final swiggy = merchants.firstWhere((m) => m.merchantKey == 'swiggy');

      expect(swiggy.merchantName, 'Swiggy');
      expect(swiggy.totalPaise, 900000);
      expect(swiggy.visits, 12);
      // ₹9,000.00 over twelve visits is ₹750.00 each.
      expect(swiggy.avgPaise, 75000);
      expect(swiggy.topCategory, 'food');
    });
  });

  group('sorting', () {
    test('starts on the biggest spend, largest first', () async {
      final container = _container(_api());
      readAndKeepAlive(container, sortedMerchantsProvider(_month));

      expect(container.read(merchantSortProvider), MerchantSort.total);
      expect(await _order(container), [
        'swiggy',
        'big basket',
        'croma',
        'uber',
      ]);
    });

    test('by visits puts the merchant gone to most often first', () async {
      final container = _container(_api());
      readAndKeepAlive(container, sortedMerchantsProvider(_month));
      await _order(container);

      container.read(merchantSortProvider.notifier).set(MerchantSort.visits);

      expect(await _order(container), [
        'swiggy',
        'uber',
        'big basket',
        'croma',
      ]);
    });

    test('by average puts the dearest visit first', () async {
      final container = _container(_api());
      readAndKeepAlive(container, sortedMerchantsProvider(_month));
      await _order(container);

      container.read(merchantSortProvider.notifier).set(MerchantSort.average);

      // Croma cost ₹4,500.00 once; Swiggy took twice as much overall but
      // only ₹750.00 at a time.
      expect(await _order(container), [
        'croma',
        'big basket',
        'swiggy',
        'uber',
      ]);
    });

    test('re-ordering does not ask the server again', () async {
      final api = _api();
      final container = _container(api);
      readAndKeepAlive(container, sortedMerchantsProvider(_month));
      await _order(container);

      container.read(merchantSortProvider.notifier).set(MerchantSort.visits);
      await _order(container);
      container.read(merchantSortProvider.notifier).set(MerchantSort.average);
      await _order(container);

      expect(api.requestsFor('GET', '/merchants'), hasLength(1));
    });

    test('loading and failure pass straight through the sort', () async {
      final api = FakeApi()..failOnce('GET', '/merchants');
      final container = _container(api);
      readAndKeepAlive(container, sortedMerchantsProvider(_month));

      expect(container.read(sortedMerchantsProvider(_month)).isLoading, isTrue);

      await expectLater(
        container.read(merchantsProvider(_month).future),
        throwsA(isA<Exception>()),
      );
      expect(container.read(sortedMerchantsProvider(_month)).hasError, isTrue);
    });
  });

  group('sortMerchants', () {
    test('ties break by total, then by key, in every order', () {
      // Two merchants, one visit each, same average: only the key can
      // separate them, and it must do so the same way every time.
      final rows = [
        merchant(merchantName: 'Zomato', totalPaise: 50000, visits: 1),
        merchant(merchantName: 'Amazon', totalPaise: 50000, visits: 1),
      ];

      for (final sort in MerchantSort.values) {
        expect(
          [for (final row in sortMerchants(rows, sort)) row.merchantKey],
          ['amazon', 'zomato'],
          reason: 'ordering by ${sort.name} must be stable',
        );
      }
    });

    test('a merchant with no visits averages nothing and sorts last', () {
      final rows = [
        // Everything this merchant charged was refunded, so there is nothing
        // left to divide.
        merchant(merchantName: 'Refunded', totalPaise: 0, visits: 0),
        merchant(merchantName: 'Swiggy', totalPaise: 900000, visits: 12),
      ];

      final byAverage = sortMerchants(rows, MerchantSort.average);

      expect(byAverage.first.merchantKey, 'swiggy');
      expect(byAverage.last.avgPaise, 0);
    });

    test('does not touch the list it was given', () {
      final rows = <MerchantInsight>[
        merchant(merchantName: 'Uber', totalPaise: 240000, visits: 8),
        merchant(merchantName: 'Croma', totalPaise: 450000, visits: 1),
      ];

      final sorted = sortMerchants(rows, MerchantSort.total);

      expect([for (final row in rows) row.merchantKey], ['uber', 'croma']);
      expect([for (final row in sorted) row.merchantKey], ['croma', 'uber']);
      expect(() => sorted.add(rows.first), throwsUnsupportedError);
    });
  });
}
