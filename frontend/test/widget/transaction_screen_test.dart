import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/core/widgets/async_error_view.dart';
import 'package:spendwise/core/widgets/empty_view.dart';
import 'package:spendwise/features/transactions/state/feed_provider.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';

import '../helpers/categories.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/test_app.dart';
import '../helpers/transactions.dart';

const String _feedPath = '/transactions';
const String _patchPath = '/transactions/txn_s1';
const String _undoPath = '/transactions/undo';
const FeedKey _feed = FeedKey(month: '2026-09');

/// Midday on 23 Sep 2026, so the feed opens on September.
final DateTime _now = DateTime(2026, 9, 23, 12);

/// Three Swiggy rows — the newest is the one the tests open — and an Uber
/// ride.
final List<Map<String, Object?>> _rows = [
  txnWire(
    id: 'txn_s1',
    merchantRaw: 'SWIGGY*1234',
    amountPaise: -45250,
    at: DateTime(2026, 9, 23, 10),
  ),
  txnWire(
    id: 'txn_u1',
    merchantName: 'Uber',
    category: 'transport',
    amountPaise: -18900,
    at: DateTime(2026, 9, 23, 8),
  ),
  txnWire(
    id: 'txn_s2',
    merchantRaw: 'SWIGGY *8891',
    amountPaise: -31000,
    at: DateTime(2026, 9, 22, 13),
  ),
  txnWire(
    id: 'txn_s3',
    merchantRaw: 'swiggy-2201',
    category: 'shopping',
    amountPaise: 9900,
    at: DateTime(2026, 9, 20, 12),
  ),
];

/// A server with the feed and the categories, and nothing else yet.
FakeApi _api() => FakeApi()
  ..on('GET', _feedPath, body: pageWire(_rows))
  ..on('GET', '/categories', body: categoriesWire());

Map<String, Object?> _patched(String category, List<String> changedIds) => {
      'updated': {..._rows.first, 'category': category},
      'changedIds': changedIds,
      'undoToken': 'undo-token-1',
    };

void _usePhoneScreen(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

TestHarness _harness(FakeApi api, {String location = Routes.transactionsPath}) {
  return routedApp(
    api,
    store: FakeSessionStore(session: testSession),
    initialLocation: location,
    overrides: [clockProvider.overrideWithValue(() => _now)],
  );
}

/// Opens the feed and taps the newest Swiggy row, the way a customer would.
Future<TestHarness> _openSwiggy(WidgetTester tester, FakeApi api) async {
  _usePhoneScreen(tester);
  final harness = _harness(api);
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Swiggy').first);
  await tester.pumpAndSettle();

  expect(harness.location, Routes.transactionDetail('txn_s1'));
  return harness;
}

String _feedCategory(TestHarness harness, String id) =>
    harness.container.read(feedProvider(_feed)).requireValue.find(id)!.category;

void main() {
  group('recategorising', () {
    testWidgets('two taps: Change category, then the category', (
      tester,
    ) async {
      final api = _api()
        ..on('PATCH', _patchPath, body: _patched('groceries', ['txn_s1']));
      final harness = await _openSwiggy(tester, api);
      expect(find.text('Food & Dining'), findsOneWidget);

      // Tap 1.
      await tester.tap(find.text('Change category'));
      await tester.pumpAndSettle();

      final toggle = find.byType(SwitchListTile);
      expect(
          find.text('Also apply to all Swiggy transactions'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      // Tap 2 — and that is the commit.
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();

      final patch = api.requestsFor('PATCH', _patchPath).single;
      expect(
          patch.jsonBody, {'category': 'groceries', 'applyToMerchant': false});
      expect(patch.idempotencyKey, isNotNull);

      expect(find.byType(SwitchListTile), findsNothing, reason: 'sheet closed');
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Food & Dining'), findsNothing);
      expect(_feedCategory(harness, 'txn_s1'), 'groceries');
      expect(_feedCategory(harness, 'txn_s2'), 'food');
      expect(api.requestsFor('GET', _feedPath), hasLength(1),
          reason: 'the feed is patched, not reloaded');

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(find.text('Moved to Groceries.'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
      expect(snackBar.duration, const Duration(seconds: 5));
      expect(
        tester.takeAnnouncements(),
        contains(
          isAccessibilityAnnouncement(
            'Moved to Groceries. Undo is available for 5 seconds.',
          ),
        ),
      );

      // The offer lapses on its own.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('Undo on the SnackBar puts the category back', (tester) async {
      final api = _api()
        ..on('PATCH', _patchPath, body: _patched('groceries', ['txn_s1']))
        ..on('POST', _undoPath, body: {
          'restoredIds': ['txn_s1'],
        });
      final harness = await _openSwiggy(tester, api);
      await tester.tap(find.text('Change category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      tester.takeAnnouncements();

      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      expect(find.text('Change undone.'), findsOneWidget);
      expect(_feedCategory(harness, 'txn_s1'), 'food');

      final undo = api.requestsFor('POST', _undoPath).single;
      expect(undo.jsonBody, {'undoToken': 'undo-token-1'});
      expect(undo.idempotencyKey, isNotNull);
      expect(
        tester.takeAnnouncements(),
        contains(
          isAccessibilityAnnouncement('Change undone. Back in Food & Dining.'),
        ),
      );
    });

    testWidgets('a 422 says what went wrong in plain words', (tester) async {
      final api = _api()
        ..respondError(
          'PATCH',
          _patchPath,
          status: 422,
          code: 'VALIDATION_FAILED',
          message: 'That category does not exist.',
          details: {'category': 'Unknown category.'},
        );
      final harness = await _openSwiggy(tester, api);
      await tester.tap(find.text('Change category'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();

      expect(
        find.text('Category not changed. That category does not exist.'),
        findsOneWidget,
      );
      expect(find.textContaining('VALIDATION_FAILED'), findsNothing);
      expect(find.textContaining('422'), findsNothing);
      expect(find.widgetWithText(SnackBarAction, 'Retry'), findsNothing,
          reason: 'the same request would fail the same way');
      expect(find.text('Food & Dining'), findsOneWidget,
          reason: 'the optimistic change was rolled back');
      expect(_feedCategory(harness, 'txn_s1'), 'food');
      expect(find.text('Change category'), findsOneWidget,
          reason: 'the button is usable again');
      expect(
        tester.takeAnnouncements(),
        contains(
          isAccessibilityAnnouncement(
            'Category not changed. That category does not exist.',
          ),
        ),
      );
    });

    testWidgets('a dropped connection offers a Retry that reuses the key', (
      tester,
    ) async {
      final api = _api()
        ..on('PATCH', _patchPath, body: _patched('groceries', ['txn_s1']))
        ..timeoutOnce('PATCH', _patchPath);
      await _openSwiggy(tester, api);
      await tester.tap(find.text('Change category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Category not changed.'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Moved to Groceries.'), findsOneWidget);
      final keys = api
          .requestsFor('PATCH', _patchPath)
          .map((request) => request.idempotencyKey)
          .toList();
      expect(keys, hasLength(2));
      expect(keys.toSet(), hasLength(1));
    });

    testWidgets('the switch takes every Swiggy transaction along', (
      tester,
    ) async {
      final api = _api()
        ..on(
          'PATCH',
          _patchPath,
          body: _patched('groceries', ['txn_s1', 'txn_s2', 'txn_s3']),
        );
      final harness = await _openSwiggy(tester, api);
      await tester.tap(find.text('Change category'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();

      expect(
        api.requestsFor('PATCH', _patchPath).single.jsonBody,
        {'category': 'groceries', 'applyToMerchant': true},
      );
      expect(
        find.text('Moved all Swiggy transactions to Groceries.'),
        findsOneWidget,
      );
      for (final id in ['txn_s1', 'txn_s2', 'txn_s3']) {
        expect(_feedCategory(harness, id), 'groceries');
      }
      expect(_feedCategory(harness, 'txn_u1'), 'transport');
    });

    testWidgets('picking the current category changes nothing', (
      tester,
    ) async {
      final api = _api();
      await _openSwiggy(tester, api);
      await tester.tap(find.text('Change category'));
      await tester.pumpAndSettle();

      await tester
          .tap(find.bySemanticsLabel('Food & Dining, current category'));
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsNothing);
      expect(api.requestsFor('PATCH', _patchPath), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('TransactionScreen states', () {
    testWidgets(
        'a deep link with nothing loaded falls back to the network, '
        'and can still be recategorised', (tester) async {
      _usePhoneScreen(tester);
      final zomato = txnWire(
        id: 'txn_z9',
        merchantName: 'Zomato',
        merchantRaw: 'ZOMATO ORDER 88121',
        amountPaise: -61200,
        at: DateTime(2026, 7, 4, 21, 5),
        mode: 'CARD',
      );
      final api = FakeApi()
        ..on('GET', _feedPath, body: pageWire([]))
        ..on('GET', '/categories', body: categoriesWire())
        ..on('GET', '/transactions/txn_z9', body: zomato)
        ..on('PATCH', '/transactions/txn_z9', body: {
          'updated': {...zomato, 'category': 'entertainment'},
          'changedIds': ['txn_z9'],
          'undoToken': 'undo-token-2',
        });
      final harness =
          _harness(api, location: Routes.transactionDetail('txn_z9'));

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(api.requestsFor('GET', '/transactions/txn_z9'), hasLength(1));
      expect(find.text('Zomato'), findsNWidgets(2));
      // The cleaned name and the descriptor the bank sent, side by side.
      expect(find.text('ZOMATO ORDER 88121'), findsOneWidget);
      expect(find.text('-₹612.00'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Sat, 4 Jul 2026, 9:05 PM'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);

      await tester.tap(find.text('Change category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entertainment'));
      await tester.pumpAndSettle();

      expect(find.text('Entertainment'), findsOneWidget);
      expect(find.text('Food & Dining'), findsNothing);
    });

    testWidgets('loading shows a skeleton', (tester) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', _feedPath, body: pageWire([]))
        ..respondAfter(
          'GET',
          '/transactions/txn_z9',
          const Duration(seconds: 1),
          body: txnWire(id: 'txn_z9'),
        );

      await tester.pumpWidget(
        _harness(api, location: Routes.transactionDetail('txn_z9')).app,
      );
      await tester.pump();
      await tester.pump();

      expect(find.bySemanticsLabel('Loading transaction'), findsOneWidget);
      expect(find.text('Change category'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Change category'), findsOneWidget);
    });

    testWidgets('a failure explains itself and retries', (tester) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', _feedPath, body: pageWire([]))
        ..on('GET', '/transactions/txn_z9', body: txnWire(id: 'txn_z9'));
      api.failOnce('GET', '/transactions/txn_z9');

      await tester.pumpWidget(
        _harness(api, location: Routes.transactionDetail('txn_z9')).app,
      );
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsOneWidget);
      expect(find.text('The bank is unavailable.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsNothing);
      expect(find.text('Change category'), findsOneWidget);
    });

    testWidgets('a transaction that does not exist is an empty state', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', _feedPath, body: pageWire([]))
        ..respondError(
          'GET',
          '/transactions/txn_gone',
          status: 404,
          code: 'TRANSACTION_NOT_FOUND',
        );
      final harness =
          _harness(api, location: Routes.transactionDetail('txn_gone'));

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('We could not find that transaction'), findsOneWidget);

      await tester.tap(find.text('Back to Spending'));
      await tester.pumpAndSettle();
      expect(harness.location, Routes.transactionsPath);
    });
  });

  group('at textScaler 2.0', () {
    testWidgets('the screen and the sheet lay out without overflow', (
      tester,
    ) async {
      _usePhoneScreen(tester, size: const Size(360, 720));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = _api()
        ..on('PATCH', _patchPath, body: _patched('education', ['txn_s1']));
      final harness = _harness(api);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Swiggy').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final change = find.text('Change category');
      await tester.scrollUntilVisible(change, 200);
      await tester.tap(change);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      Finder inSheet(Finder finder) =>
          find.descendant(of: find.byType(BottomSheet), matching: finder);

      // One column: two would break "Entertainment" mid-word at this size.
      final food = tester.getRect(inSheet(find.text('Food & Dining')));
      final groceries = tester.getRect(inSheet(find.text('Groceries')));
      expect(groceries.top, greaterThan(food.bottom));

      final education = inSheet(find.text('Education'));
      await tester.scrollUntilVisible(
        education,
        300,
        scrollable: inSheet(find.byType(Scrollable)),
      );
      await tester.tap(education);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Moved to Education.'), findsOneWidget);
    });
  });
}
