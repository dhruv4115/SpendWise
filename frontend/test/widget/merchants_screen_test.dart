import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/core/widgets/async_error_view.dart';
import 'package:spendwise/core/widgets/empty_view.dart';
import 'package:spendwise/features/merchants/state/merchants_provider.dart';
import 'package:spendwise/features/merchants/widgets/merchant_tile.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';
import 'package:spendwise/features/transactions/widgets/transaction_tile.dart';

import '../helpers/categories.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/merchants.dart';
import '../helpers/test_app.dart';
import '../helpers/transactions.dart';

final DateTime _now = DateTime(2026, 9, 23, 12);

/// Three merchants whose orders differ under every sort:
///
/// | merchant   |  total |  visits | average |
/// |------------|--------|---------|---------|
/// | Swiggy     | ₹9,000 |      12 |    ₹750 |
/// | Big Basket | ₹6,000 |       3 |  ₹2,000 |
/// | Uber       | ₹2,400 |       8 |    ₹300 |
final List<Map<String, Object?>> _three = [
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
];

FakeApi _api({List<Map<String, Object?>>? merchants}) => FakeApi()
  ..on('GET', '/categories', body: categoriesWire())
  ..on('GET', '/merchants', body: merchantsWire(merchants ?? _three));

TestHarness _harness(FakeApi api) => routedApp(
      api,
      store: FakeSessionStore(session: testSession),
      initialLocation: Routes.merchantsPath,
      overrides: [clockProvider.overrideWithValue(() => _now)],
    );

void _usePhoneScreen(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<TestHarness> _open(WidgetTester tester, FakeApi api) async {
  _usePhoneScreen(tester);
  final harness = _harness(api);
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}

/// The merchants on screen, top to bottom.
List<String> _order(WidgetTester tester) => [
      for (final tile in tester.widgetList<MerchantTile>(
        find.byType(MerchantTile),
      ))
        tile.insight.merchantKey,
    ];

/// Opens the sort menu and picks [label].
Future<void> _sortBy(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Sort merchants'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('states', () {
    testWidgets('loading shows skeletons, then the merchants', (tester) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', '/categories', body: categoriesWire())
        ..respondAfter(
          'GET',
          '/merchants',
          const Duration(seconds: 1),
          body: merchantsWire(_three),
        );

      await tester.pumpWidget(_harness(api).app);
      await tester.pump();
      await tester.pump();

      expect(find.bySemanticsLabel('Loading merchants'), findsOneWidget);
      expect(find.byType(MerchantTile), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(MerchantTile), findsNWidgets(3));
      expect(find.bySemanticsLabel('Loading merchants'), findsNothing);
    });

    testWidgets('a failure explains itself and recovers on Retry',
        (tester) async {
      _usePhoneScreen(tester);
      final api = _api()..failOnce('GET', '/merchants');

      await tester.pumpWidget(_harness(api).app);
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsOneWidget);
      expect(find.text('We could not load your merchants'), findsOneWidget);
      expect(find.text('The bank is unavailable.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsNothing);
      expect(find.byType(MerchantTile), findsNWidgets(3));
    });

    testWidgets('a month with nothing spent says so', (tester) async {
      await _open(tester, _api(merchants: const []));

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('Nothing spent in September 2026'), findsOneWidget);
      expect(find.byType(MerchantTile), findsNothing);
    });
  });

  group('the list', () {
    testWidgets('shows the total, the visits and the average on every row',
        (tester) async {
      await _open(tester, _api());

      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('₹9,000.00'), findsOneWidget);
      expect(find.text('12 payments · ₹750.00 avg'), findsOneWidget);
      // The category is named, not only drawn as an icon.
      expect(find.text('Food & Dining'), findsOneWidget);
    });

    testWidgets('a screen reader hears the whole row as a sentence',
        (tester) async {
      await _open(tester, _api());

      expect(
        find.bySemanticsLabel(
          'Big Basket. ₹6,000.00 over 3 payments, ₹2,000.00 on average. '
          'Groceries.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping a merchant opens their month', (tester) async {
      final api = _api()
        ..on(
          'GET',
          '/transactions',
          body: pageWire([
            txnWire(id: 'txn_1', merchantName: 'Swiggy', amountPaise: -45000),
            txnWire(id: 'txn_2', merchantName: 'Swiggy', amountPaise: -30000),
          ]),
        );
      final harness = await _open(tester, api);

      await tester.tap(find.text('Swiggy'));
      await tester.pumpAndSettle();

      expect(harness.location, '/merchants/swiggy');
      expect(find.text('Total spent'), findsOneWidget);
      expect(find.byType(TransactionTile), findsNWidgets(2));
      // Every payment is in one category, so there is a rule to report.
      expect(
        find.text('Every Swiggy payment this month is in Food & Dining.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          FilledButton,
          'Change category for all Swiggy',
        ),
        findsOneWidget,
      );
    });
  });

  group('the sort control', () {
    testWidgets('starts on the biggest spend and says so', (tester) async {
      await _open(tester, _api());

      expect(_order(tester), ['swiggy', 'big basket', 'uber']);
      expect(find.text('3 merchants · Most spent first'), findsOneWidget);
      // An icon-only button always says what it is.
      expect(find.byTooltip('Sort merchants'), findsOneWidget);
    });

    testWidgets('offers three orders, with the current one ticked',
        (tester) async {
      await _open(tester, _api());

      await tester.tap(find.byTooltip('Sort merchants'));
      await tester.pumpAndSettle();

      expect(find.text('Total spent'), findsOneWidget);
      expect(find.text('Number of visits'), findsOneWidget);
      expect(find.text('Average spend'), findsOneWidget);
      final items = tester
          .widgetList<CheckedPopupMenuItem<MerchantSort>>(
            find.byType(CheckedPopupMenuItem<MerchantSort>),
          )
          .toList();
      expect(
        {for (final item in items) item.value: item.checked},
        {
          MerchantSort.total: true,
          MerchantSort.visits: false,
          MerchantSort.average: false,
        },
      );
    });

    testWidgets('by visits reorders the list without asking again',
        (tester) async {
      final api = _api();
      await _open(tester, api);

      await _sortBy(tester, 'Number of visits');

      expect(_order(tester), ['swiggy', 'uber', 'big basket']);
      expect(find.text('3 merchants · Most visits first'), findsOneWidget);
      expect(api.requestsFor('GET', '/merchants'), hasLength(1));
    });

    testWidgets('by average puts the dearest visit first', (tester) async {
      await _open(tester, _api());

      await _sortBy(tester, 'Average spend');

      expect(_order(tester), ['big basket', 'swiggy', 'uber']);
      expect(find.text('3 merchants · Highest average first'), findsOneWidget);
    });
  });

  testWidgets('does not overflow at textScaler 2.0 on a narrow screen',
      (tester) async {
    _usePhoneScreen(tester, size: const Size(320, 800));

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(tester.view)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: _harness(_api()).app,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Swiggy'), findsOneWidget);

    // The rows below the fold are laid out at this size too, not only the
    // first one.
    await tester.dragUntilVisible(
      find.text('Uber'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
