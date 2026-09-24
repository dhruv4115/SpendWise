import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/core/widgets/empty_view.dart';
import 'package:spendwise/features/transactions/domain/transaction_filter.dart';
import 'package:spendwise/features/transactions/presentation/feed_screen.dart';
import 'package:spendwise/features/transactions/presentation/filters_sheet.dart';
import 'package:spendwise/features/transactions/state/filter_provider.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';

import '../helpers/categories.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/test_app.dart';
import '../helpers/transactions.dart';

const String _path = '/transactions';

/// The month the feed opens on.
const Map<String, String> _thisMonth = {'month': '2026-09'};

/// Midday on 23 Sep 2026, so the feed opens on September.
final DateTime _now = DateTime(2026, 9, 23, 12);

final Map<String, Object?> _swiggy = txnWire(
  id: 'txn_s1',
  amountPaise: -45250,
  at: DateTime(2026, 9, 23, 10),
);
final Map<String, Object?> _uber = txnWire(
  id: 'txn_u1',
  merchantName: 'Uber',
  category: 'transport',
  amountPaise: -18900,
  at: DateTime(2026, 9, 23, 8),
);
final Map<String, Object?> _bigBasket = txnWire(
  id: 'txn_g1',
  merchantName: 'BigBasket',
  category: 'groceries',
  amountPaise: -120000,
  at: DateTime(2026, 9, 22, 19),
);
final Map<String, Object?> _dmart = txnWire(
  id: 'txn_g2',
  merchantName: 'DMart',
  category: 'groceries',
  amountPaise: -64000,
  at: DateTime(2026, 9, 20, 11),
);

Map<String, Object?> _everything() =>
    pageWire([_swiggy, _uber, _bigBasket, _dmart]);
Map<String, Object?> _groceries() => pageWire([_bigBasket, _dmart]);

/// The unfiltered month first, then — the fake cannot filter — whatever a
/// filtered request should see.
FakeApi _api({Map<String, Object?>? filtered, Duration? filteredDelay}) {
  return FakeApi()
    ..on('GET', '/categories', body: categoriesWire())
    ..on('GET', _path, times: 1, query: _thisMonth, body: _everything())
    ..on('GET', _path, body: filtered ?? _groceries(), delay: filteredDelay);
}

void _usePhoneScreen(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<TestHarness> _openFeed(
  WidgetTester tester,
  FakeApi api, {
  String location = Routes.transactionsPath,
}) async {
  final harness = routedApp(
    api,
    store: FakeSessionStore(session: testSession),
    initialLocation: location,
    overrides: [clockProvider.overrideWithValue(() => _now)],
  );
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}

/// Opens the sheet from the filter button, picks [category] and a
/// [minimum], and taps Apply. Leaves the frames to the caller.
Future<void> _filterInSheet(
  WidgetTester tester, {
  required String category,
  String? minimum,
}) async {
  await tester.tap(find.byIcon(Icons.tune));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ChoiceChip, category));
  await tester.pump();
  if (minimum != null) {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Minimum'),
      minimum,
    );
  }
  await tester.tap(find.text('Apply'));
}

Finder get _searchField => find.descendant(
      of: find.byType(SearchBar),
      matching: find.byType(TextField),
    );

String _searchText(WidgetTester tester) =>
    tester.widget<TextField>(_searchField).controller!.text;

Finder _chip(String label) => find.widgetWithText(InputChip, label);

/// Every request the feed made for the month under test — and none of the
/// ones the month strip made to have its neighbours ready.
List<RecordedRequest> _feedRequests(FakeApi api) =>
    api.requestsFor('GET', _path, query: _thisMonth);

void main() {
  group('filters survive navigation', () {
    testWidgets(
        'applying a filter, opening a transaction and coming back keeps the '
        'filter and the chip row', (tester) async {
      _usePhoneScreen(tester);
      final api = _api();
      final harness = await _openFeed(tester, api);
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.byTooltip('Filters'), findsOneWidget);

      await _filterInSheet(tester, category: 'Groceries', minimum: '100');
      await tester.pumpAndSettle();

      const applied = TransactionFilter(category: 'groceries', minPaise: 10000);
      expect(harness.container.read(filterStateNotifier), applied);
      expect(_chip('Groceries'), findsOneWidget);
      expect(_chip('At least ₹100.00'), findsOneWidget);
      expect(find.byTooltip('Filters, 2 applied'), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
      expect(find.text('BigBasket'), findsOneWidget);
      final request = _feedRequests(api).last.query;
      expect(request['category'], 'groceries');
      expect(request['minPaise'], '10000');
      final requestsBefore = _feedRequests(api).length;

      await tester.tap(find.text('BigBasket'));
      await tester.pumpAndSettle();
      expect(harness.location, Routes.transactionDetail('txn_g1'));

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(harness.location, Routes.transactionsPath);
      expect(harness.container.read(filterStateNotifier), applied);
      expect(_chip('Groceries'), findsOneWidget);
      expect(_chip('At least ₹100.00'), findsOneWidget);
      expect(find.byTooltip('Filters, 2 applied'), findsOneWidget);
      expect(find.text('BigBasket'), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
      expect(_feedRequests(api), hasLength(requestsBefore),
          reason: 'the filtered feed was kept, not fetched again');
    });

    testWidgets('a feed screen built from scratch comes back filtered', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = _api();
      final harness = await _openFeed(tester, api);

      await tester.enterText(_searchField, 'big');
      await tester.pump(FeedScreen.searchDebounce);
      await _filterInSheet(tester, category: 'Groceries');
      await tester.pumpAndSettle();
      expect(_chip('“big”'), findsOneWidget);

      // Throw the whole widget tree away — every screen, every State — and
      // build it again on the same providers.
      await tester.pumpWidget(const SizedBox());
      expect(find.byType(FeedScreen), findsNothing);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.byType(FeedScreen), findsOneWidget);
      expect(_chip('Groceries'), findsOneWidget);
      expect(_chip('“big”'), findsOneWidget);
      expect(_searchText(tester), 'big',
          reason: 'a new search field starts from the filter');
      final request = _feedRequests(api).last.query;
      expect(request['category'], 'groceries');
      expect(request['q'], 'big');
    });
  });

  group('search', () {
    testWidgets('waits for a 300 ms pause, then sends one request', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = _api(filtered: pageWire([_bigBasket]));
      final harness = await _openFeed(tester, api);

      await tester.enterText(_searchField, 'b');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(_searchField, 'bi');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(_searchField, 'big ');
      await tester.pump(const Duration(milliseconds: 299));

      expect(_feedRequests(api), hasLength(1), reason: 'still typing');
      expect(harness.container.read(filterStateNotifier).query, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(_feedRequests(api), hasLength(2));
      expect(_feedRequests(api).last.query['q'], 'big');
      expect(harness.container.read(filterStateNotifier).query, 'big');
      expect(find.text('Swiggy'), findsNothing);
      expect(find.text('BigBasket'), findsOneWidget);
      expect(find.byTooltip('Filters, 1 applied'), findsOneWidget);
    });

    testWidgets("the chip's X clears the search and the field with it", (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = _api(filtered: pageWire([_bigBasket]));
      await _openFeed(tester, api);
      await tester.enterText(_searchField, 'big');
      await tester.pump(FeedScreen.searchDebounce);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove search'));
      await tester.pumpAndSettle();

      expect(_searchText(tester), isEmpty);
      expect(find.byType(InputChip), findsNothing);
      expect(find.byTooltip('Filters'), findsOneWidget);
      // The unfiltered month is one of the three kept resident, so clearing
      // the search returns to rows that never left memory.
      expect(find.text('Swiggy'), findsOneWidget);
      expect(
        _feedRequests(api),
        hasLength(2),
        reason: 'one unfiltered page and one filtered one, and no more',
      );
    });
  });

  group('changing the filter', () {
    testWidgets('the old rows stay under "Filtering…" until the new ones land',
        (tester) async {
      _usePhoneScreen(tester);
      final api = _api(filteredDelay: const Duration(seconds: 1));
      await _openFeed(tester, api);

      await _filterInSheet(tester, category: 'Groceries');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(FiltersSheet), findsNothing);
      expect(find.text('Filtering…'), findsOneWidget);
      expect(find.text('Swiggy'), findsOneWidget,
          reason: 'the previous rows are still underneath');
      expect(_chip('Groceries'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Filtering…'), findsNothing);
      expect(find.text('Swiggy'), findsNothing);
      expect(find.text('BigBasket'), findsOneWidget);
      expect(
          find.text("That's every match in September 2026."), findsOneWidget);
    });

    testWidgets('a chip X removes that filter and keeps the others', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = _api();
      final harness = await _openFeed(tester, api);
      await _filterInSheet(tester, category: 'Groceries', minimum: '100');
      await tester.pumpAndSettle();

      // The row scrolls sideways; the second chip may start off screen.
      await tester.ensureVisible(find.byTooltip('Remove amount filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove amount filter'));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(filterStateNotifier),
        const TransactionFilter(category: 'groceries'),
      );
      expect(_chip('Groceries'), findsOneWidget);
      expect(_chip('At least ₹100.00'), findsNothing);
      final request = _feedRequests(api).last.query;
      expect(request['category'], 'groceries');
      expect(request.containsKey('minPaise'), isFalse);
    });
  });

  group('empty states', () {
    testWidgets('no results for these filters, with a way out', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', '/categories', body: categoriesWire())
        ..on('GET', _path, times: 1, query: _thisMonth, body: _everything())
        ..on('GET', _path, times: 1, query: _thisMonth, body: pageWire([]))
        ..on('GET', _path, body: _everything());
      final harness = await _openFeed(tester, api);

      await _filterInSheet(tester, category: 'Travel');
      await tester.pumpAndSettle();

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('No results for these filters'), findsOneWidget);
      expect(find.text('No transactions in September 2026'), findsNothing);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(filterStateNotifier),
        TransactionFilter.none,
      );
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('Swiggy'), findsOneWidget);
      // Back to rows that were still in memory: the unfiltered month is held
      // open, so clearing a filter costs nothing.
      expect(
        _feedRequests(api),
        hasLength(2),
        reason: 'one unfiltered page and one filtered one, and no more',
      );
    });

    testWidgets('an empty month with no filter says so instead', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', '/categories', body: categoriesWire())
        ..on('GET', _path, body: pageWire([]));
      await _openFeed(tester, api);

      expect(find.text('No transactions in September 2026'), findsOneWidget);
      expect(find.text('No results for these filters'), findsNothing);
      expect(find.text('Clear filters'), findsNothing);
    });
  });

  group('the address seeds the filter', () {
    testWidgets('?category= is applied before the first request', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', '/categories', body: categoriesWire())
        ..on('GET', _path, body: _groceries());
      final harness = await _openFeed(
        tester,
        api,
        location: Routes.transactionsInCategory('groceries'),
      );

      expect(
        harness.container.read(filterStateNotifier),
        const TransactionFilter(category: 'groceries'),
      );
      expect(_chip('Groceries'), findsOneWidget);
      expect(find.byTooltip('Filters, 1 applied'), findsOneWidget);
      final requests = _feedRequests(api);
      expect(requests, hasLength(1),
          reason: 'no unfiltered request thrown away a frame later');
      expect(requests.single.query['category'], 'groceries');
    });
  });

  group('at textScaler 2.0', () {
    testWidgets('search, badge, chips and rows fit without overflow', (
      tester,
    ) async {
      _usePhoneScreen(tester, size: const Size(360, 720));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = _api();
      final harness = await _openFeed(tester, api);

      harness.container.read(filterStateNotifier.notifier).applyAll(
            TransactionFilter(
              category: 'groceries',
              query: 'big',
              minPaise: 10000,
              maxPaise: 500000,
              from: DateTime(2026, 9, 1),
              to: DateTime(2026, 9, 22, 23, 59, 59, 999),
            ),
          );
      await tester.pumpAndSettle();

      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(SearchBar)))
            .scale(10),
        20,
        reason: 'the test must really be running at 2.0',
      );
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Filters, 4 applied'), findsOneWidget);
      expect(_chip('Groceries'), findsOneWidget);
      expect(find.text('BigBasket'), findsOneWidget);
    });
  });
}
