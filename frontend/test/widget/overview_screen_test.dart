import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/core/utils/money.dart';
import 'package:spendwise/core/widgets/async_error_view.dart';
import 'package:spendwise/core/widgets/empty_view.dart';
import 'package:spendwise/features/overview/presentation/overview_screen.dart';
import 'package:spendwise/features/overview/state/overview_provider.dart';
import 'package:spendwise/features/overview/widgets/chart_table_view.dart';
import 'package:spendwise/features/overview/widgets/daily_spend_line.dart';
import 'package:spendwise/features/overview/widgets/spend_donut.dart';
import 'package:spendwise/features/overview/widgets/summary_header_card.dart';
import 'package:spendwise/features/transactions/presentation/feed_screen.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';

import '../helpers/categories.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/summaries.dart';
import '../helpers/test_app.dart';
import '../helpers/transactions.dart';

const String _month = '2026-09';
final DateTime _now = DateTime(2026, 9, 23, 12);

/// A server with September's summary, the categories, and a feed whose
/// first page is not its last — so the Overview shows the server's numbers.
FakeApi _api({Map<String, Object?>? summary}) => FakeApi()
  ..on('GET', '/summary', body: summary ?? septemberWire())
  ..on('GET', '/categories', body: categoriesWire())
  ..on('GET', '/transactions', body: pageWire(spendsWire(3), nextCursor: 'c2'));

TestHarness _harness(FakeApi api) => routedApp(
      api,
      store: FakeSessionStore(session: testSession),
      initialLocation: Routes.overviewPath,
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

Finder get _tablesSwitch =>
    find.widgetWithText(SwitchListTile, 'View as table');

void main() {
  group('OverviewScreen states', () {
    testWidgets('loading shows skeleton cards, then the month', (tester) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..respondAfter('GET', '/summary', const Duration(seconds: 1),
            body: septemberWire())
        ..on('GET', '/categories', body: categoriesWire())
        ..on('GET', '/transactions',
            body: pageWire(spendsWire(3), nextCursor: 'c2'));

      await tester.pumpWidget(_harness(api).app);
      await tester.pump();
      await tester.pump();

      expect(find.bySemanticsLabel('Loading overview'), findsOneWidget);
      expect(find.byType(SpendDonut), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Loading overview'), findsNothing);
      expect(find.byType(SpendDonut), findsOneWidget);
    });

    testWidgets('a failure explains itself, and Retry loads the month', (
      tester,
    ) async {
      final api = _api()..failOnce('GET', '/summary');
      await _open(tester, api);

      expect(find.byType(AsyncErrorView), findsOneWidget);
      expect(find.text('We could not load your overview'), findsOneWidget);
      expect(find.text('The bank is unavailable.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsNothing);
      expect(find.byType(SummaryHeaderCard), findsOneWidget);
      expect(api.requestsFor('GET', '/summary'), hasLength(2));
    });

    testWidgets('the header, the donut and the line', (tester) async {
      final api = _api();
      await _open(tester, api);

      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('Spent in September 2026'), findsOneWidget);
      expect(find.text('₹10,900.00'), findsOneWidget);
      // An arrow, and the word — never the colour alone.
      expect(find.text('₹900.00 (9%) more than last month'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

      expect(find.byType(SpendDonut), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('₹4,500.00 · 41%'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Health'), findsNothing, reason: 'folded into Other');

      await tester.scrollUntilVisible(find.byType(DailySpendLine), 300);
      expect(find.byType(DailySpendLine), findsOneWidget);
      // Each chart repaints on its own.
      for (final chart in [PieChart, LineChart]) {
        expect(
          find.ancestor(
            of: find.byType(chart),
            matching: find.byType(RepaintBoundary),
          ),
          findsWidgets,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty month shows the empty view, not an empty chart', (
      tester,
    ) async {
      final api = _api(summary: summaryWire(prevTotalPaise: 500000));
      await _open(tester, api);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('Nothing spent in September 2026'), findsOneWidget);
      expect(find.byType(SpendDonut), findsNothing);
      expect(find.byType(DailySpendLine), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(api.requestsFor('GET', '/summary'), hasLength(2));
    });
  });

  group('the table alternative', () {
    testWidgets('swaps each chart for a table of the same numbers', (
      tester,
    ) async {
      final harness = await _open(tester, _api());
      final data =
          harness.container.read(overviewProvider(_month)).requireValue;

      // Reachable by a screen reader as a switch it can flip.
      expect(
        tester.getSemantics(_tablesSwitch),
        isSemantics(
          label: 'View as table\nEach chart as rows of numbers',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );

      await tester.tap(_tablesSwitch);
      await tester.pumpAndSettle();

      expect(find.byType(SpendDonut), findsNothing);
      expect(find.byType(ChartTableView), findsWidgets);

      final categoryTable = find.byType(DataTable).first;
      Finder inTable(String text) =>
          find.descendant(of: categoryTable, matching: find.text(text));
      var total = 0;
      for (final slice in data.slices) {
        expect(inTable(slice.label), findsOneWidget);
        expect(inTable(formatPaise(slice.paise)), findsOneWidget);
        expect(inTable('${slice.sharePercent}%'), findsWidgets);
        total += slice.paise;
      }
      // The table adds up to what the donut drew, and to 100%.
      expect(inTable('Total'), findsOneWidget);
      expect(inTable(formatPaise(total)), findsOneWidget);
      expect(inTable('100%'), findsOneWidget);
      expect(total, data.chartedPaise);

      // The day table is further down the page, built as it scrolls in.
      await tester.scrollUntilVisible(
        find.text('9 Sep'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(DailySpendLine), findsNothing);
      final dayTable = find.ancestor(
        of: find.text('9 Sep'),
        matching: find.byType(DataTable),
      );
      expect(dayTable, findsOneWidget);
      expect(
        find.descendant(of: dayTable, matching: find.text('₹4,000.00')),
        findsOneWidget,
      );

      // The choice outlives the screen's rebuilds.
      expect(harness.container.read(chartTablesProvider), isTrue);
    });
  });

  group('filtering the feed', () {
    testWidgets('tapping a slice opens the feed for that category', (
      tester,
    ) async {
      final api = _api();
      final harness = await _open(tester, api);

      // Food is the first slice: 41% clockwise from twelve o'clock. Aim at
      // the middle of its arc, halfway through the ring.
      const midAngle = -math.pi / 2 + math.pi * 0.41;
      const radius = SpendDonut.holeRadius + SpendDonut.ringWidth / 2;
      final centre = tester.getCenter(find.byType(PieChart));
      await tester.tapAt(
        centre +
            Offset(radius * math.cos(midAngle), radius * math.sin(midAngle)),
      );
      await tester.pumpAndSettle();

      expect(harness.location, '/transactions?category=food');
      expect(find.byType(FeedScreen), findsOneWidget);
      expect(
        api.requestsFor('GET', '/transactions').last.query['category'],
        'food',
      );
      expect(find.widgetWithText(InputChip, 'Food & Dining'), findsOneWidget);

      // Back goes back to the Overview it came from.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(harness.location, Routes.overviewPath);
      expect(find.byType(OverviewScreen), findsOneWidget);
    });

    testWidgets('a legend row does the same; the fold does nothing', (
      tester,
    ) async {
      final api = _api();
      final harness = await _open(tester, api);

      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(harness.location, Routes.overviewPath);

      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      expect(harness.location, '/transactions?category=groceries');

      // Clearing the chip shows every category.
      await tester.tap(find.byTooltip('Show every category'));
      await tester.pumpAndSettle();
      expect(harness.location, Routes.transactionsPath);
      expect(find.byType(InputChip), findsNothing);
      expect(
        api
            .requestsFor('GET', '/transactions')
            .last
            .query
            .containsKey('category'),
        isFalse,
      );
    });
  });

  group('refreshing', () {
    testWidgets('pull-to-refresh fetches the summary again, over the charts', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('GET', '/summary', times: 1, body: septemberWire())
        ..respondAfter('GET', '/summary', const Duration(seconds: 2),
            body: summaryWire(
              byCategory: const {'food': 100000},
              prevTotalPaise: 1000000,
            ))
        ..on('GET', '/categories', body: categoriesWire())
        ..on('GET', '/transactions',
            body: pageWire(spendsWire(3), nextCursor: 'c2'));
      await _open(tester, api);

      await tester.fling(
        find.byType(SummaryHeaderCard),
        const Offset(0, 400),
        1000,
      );
      // The indicator snaps into place over a few frames, then refreshes.
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Mid-refresh: the old month stays up under the spinner — no
      // skeleton flash.
      expect(api.requestsFor('GET', '/summary'), hasLength(2));
      expect(find.bySemanticsLabel('Loading overview'), findsNothing);
      expect(find.text('₹10,900.00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('₹1,000.00'), findsOneWidget);
      expect(find.text('₹9,000.00 (90%) less than last month'), findsOneWidget);
    });

    testWidgets('the month arrows move the Overview', (tester) async {
      final api = _api();
      await _open(tester, api);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();

      expect(find.text('August 2026'), findsOneWidget);
      expect(api.requestsFor('GET', '/summary').last.query['month'], '2026-08');
    });
  });

  group('at textScaler 2.0', () {
    Future<TestHarness> openLarge(WidgetTester tester, FakeApi api) async {
      _usePhoneScreen(tester, size: const Size(360, 720));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final harness = _harness(api);
      await tester.pumpWidget(harness.app);
      return harness;
    }

    testWidgets('charts and tables lay out without overflow', (tester) async {
      await openLarge(tester, _api());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(find.byType(DailySpendLine), 300);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(_tablesSwitch, -300);
      await tester.tap(_tablesSwitch);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Amounts by day'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading, error and empty lay out without overflow', (
      tester,
    ) async {
      await openLarge(
        tester,
        FakeApi()
          ..respondAfter('GET', '/summary', const Duration(seconds: 1),
              body: summaryWire())
          ..on('GET', '/categories', body: categoriesWire())
          ..on('GET', '/transactions', body: pageWire([])),
      );
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('Loading overview'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(EmptyView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the error view lays out without overflow', (tester) async {
      await openLarge(
        tester,
        FakeApi()
          ..respondError('GET', '/summary', status: 503, code: 'DOWN')
          ..on('GET', '/categories', body: categoriesWire())
          ..on('GET', '/transactions', body: pageWire([])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
