import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/core/cache/offline_cache.dart';
import 'package:spendwise/core/widgets/skeleton.dart';
import 'package:spendwise/features/transactions/presentation/month_switcher.dart';
import 'package:spendwise/features/transactions/state/feed_provider.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';

import '../helpers/categories.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_cache.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/test_app.dart';
import '../helpers/transactions.dart';

const String _path = '/transactions';

/// Midday on 23 Sep 2026, so the window runs March to September.
final DateTime _now = DateTime(2026, 9, 23, 12);

Map<String, String> _month(String month) => {'month': month};

/// A month whose rows name it, so the screen says which month it is showing
/// without anyone having to read the strip.
Map<String, Object?> _page(String label, DateTime at) => pageWire([
      txnWire(id: 'txn_$label', merchantName: label, at: at),
    ]);

FakeApi _api() => FakeApi()
  ..on('GET', '/categories', body: categoriesWire())
  ..on(
    'GET',
    _path,
    query: _month('2026-09'),
    body: _page('September Rent', DateTime(2026, 9, 3, 9)),
  )
  ..on(
    'GET',
    _path,
    query: _month('2026-08'),
    body: _page('August Rent', DateTime(2026, 8, 3, 9)),
  )
  ..on(
    'GET',
    _path,
    query: _month('2026-07'),
    body: _page('July Rent', DateTime(2026, 7, 3, 9)),
  );

void _usePhoneScreen(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<TestHarness> _openFeed(
  WidgetTester tester,
  FakeApi api, {
  OfflineCache? cache,
}) async {
  _usePhoneScreen(tester);
  final harness = routedApp(
    api,
    store: FakeSessionStore(session: testSession),
    initialLocation: Routes.transactionsPath,
    cache: cache,
    overrides: [clockProvider.overrideWithValue(() => _now)],
  );
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}

/// A swipe to the right, which brings the month on the left — the previous
/// one — into view.
///
/// One page is a little under half the strip, so 80 logical pixels is over
/// half a page and under a page and a half: it snaps back exactly one month.
Future<void> _swipeBack(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(80, 0));
}

void main() {
  group('the strip', () {
    testWidgets('offers six months back and this one, and no further', (
      tester,
    ) async {
      final harness = await _openFeed(tester, _api());

      expect(harness.container.read(monthWindowProvider), hasLength(7));
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.byType(MonthSwitcher), findsOneWidget);

      // Forward from this month is a blank page, so the arrow is dead.
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNull);
      expect(find.byTooltip('Next month'), findsOneWidget);
      expect(find.byTooltip('Previous month'), findsOneWidget);
    });

    testWidgets('the back arrow dies at the oldest month on offer', (
      tester,
    ) async {
      final api = _api()..on('GET', _path, body: pageWire([]));
      final harness = await _openFeed(tester, api);

      for (var step = 0; step < 6; step++) {
        await tester.tap(find.byTooltip('Previous month'));
        await tester.pumpAndSettle();
      }

      expect(harness.container.read(monthProvider), '2026-03');
      final back = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(back.onPressed, isNull);
    });
  });

  group('swiping', () {
    testWidgets('a warmed month arrives without a loading state', (
      tester,
    ) async {
      final api = _api();
      final harness = await _openFeed(tester, api);

      expect(find.text('September Rent'), findsOneWidget);
      // The month beside this one was fetched while the customer was reading
      // this one, so it is sitting in memory before the swipe starts.
      final august = feedProvider(const FeedKey(month: '2026-08'));
      expect(harness.container.read(august).hasValue, isTrue);
      expect(api.requestsFor('GET', _path, query: _month('2026-08')),
          hasLength(1));

      await _swipeBack(tester);

      // Every frame of the swipe, not just the one it settles on.
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          find.byType(SkeletonList),
          findsNothing,
          reason: 'a month already in memory never shows a skeleton',
        );
      }
      await tester.pumpAndSettle();

      expect(harness.container.read(monthProvider), '2026-08');
      expect(find.text('August Rent'), findsOneWidget);
      expect(find.text('September Rent'), findsNothing);
      expect(
        api.requestsFor('GET', _path, query: _month('2026-08')),
        hasLength(1),
        reason: 'arriving on a warm month asks the server for nothing',
      );
    });

    testWidgets('swiping warms the month beyond it in turn', (tester) async {
      final api = _api();
      final harness = await _openFeed(tester, api);
      expect(api.requestsFor('GET', _path, query: _month('2026-07')), isEmpty);

      await _swipeBack(tester);
      await tester.pumpAndSettle();

      expect(harness.container.read(monthProvider), '2026-08');
      expect(
        api.requestsFor('GET', _path, query: _month('2026-07')),
        hasLength(1),
        reason: 'the next step back is ready before it is asked for',
      );
    });

    testWidgets('the arrows and the strip stay in step', (tester) async {
      final harness = await _openFeed(tester, _api());

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();

      expect(harness.container.read(monthProvider), '2026-08');
      // The page slid to match, rather than the strip and the list
      // disagreeing about which month is on screen.
      final pages = tester.widget<PageView>(find.byType(PageView));
      expect(pages.controller!.page!.round(), 5);
      expect(find.text('August Rent'), findsOneWidget);
    });
  });

  group('saved data', () {
    testWidgets('a month in the cache still opens when the bank is gone', (
      tester,
    ) async {
      final saved = FakeOfflineCache()
        ..seed(
          transactionsCacheKey('2026-09'),
          _page('September Rent', DateTime(2026, 9, 3, 9)),
          age: const Duration(hours: 2),
        );
      final api = FakeApi()
        ..on('GET', '/categories', body: categoriesWire())
        // The first ask for this month never comes back; the second does.
        ..timeoutOnce('GET', _path, query: _month('2026-09'))
        ..on(
          'GET',
          _path,
          query: _month('2026-09'),
          body: _page('September Rent', DateTime(2026, 9, 3, 9)),
        )
        ..on('GET', _path, body: pageWire([]));

      await _openFeed(tester, api, cache: saved);

      // The rows are there, and the screen says where they came from.
      expect(find.text('September Rent'), findsOneWidget);
      expect(find.textContaining('Showing saved data from'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.byType(SkeletonList), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Showing saved data from'), findsNothing);
      expect(find.text('September Rent'), findsOneWidget);
    });

    testWidgets('a month that is not saved anywhere still fails honestly', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('GET', '/categories', body: categoriesWire())
        ..timeoutOnce('GET', _path, query: _month('2026-09'))
        ..on('GET', _path, body: pageWire([]));

      await _openFeed(tester, api);

      expect(find.textContaining('Showing saved data from'), findsNothing);
      expect(
        find.textContaining('We could not reach your bank'),
        findsOneWidget,
      );
    });
  });
}
