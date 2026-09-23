import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/core/widgets/async_error_view.dart';
import 'package:spendwise/core/widgets/empty_view.dart';
import 'package:spendwise/features/budgets/widgets/budget_card.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';

import '../helpers/budgets.dart';
import '../helpers/categories.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/summaries.dart';
import '../helpers/test_app.dart';

final DateTime _now = DateTime(2026, 9, 23, 12);

/// Three budgets, one in each state: half spent, 85% spent, and a fifth over.
final List<Map<String, Object?>> _threeStates = [
  budgetWire(category: 'food', limitPaise: 500000, spentPaise: 250000),
  budgetWire(category: 'transport', limitPaise: 200000, spentPaise: 170000),
  budgetWire(category: 'shopping', limitPaise: 100000, spentPaise: 120000),
];

FakeApi _api({List<Map<String, Object?>>? budgets}) => FakeApi()
  ..on('GET', '/categories', body: categoriesWire())
  ..on('GET', '/budgets', body: budgetsWire(budgets ?? _threeStates));

TestHarness _harness(FakeApi api) => routedApp(
      api,
      store: FakeSessionStore(session: testSession),
      initialLocation: Routes.budgetsPath,
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

void main() {
  group('risk badges', () {
    testWidgets('each state says what it is, in words and in an icon', (
      tester,
    ) async {
      await _open(tester, _api());

      expect(find.byType(BudgetCard), findsNWidgets(3));

      // The words. Colour is never asked to carry this on its own.
      expect(find.text('On track'), findsOneWidget);
      expect(find.text('Nearing limit'), findsOneWidget);
      expect(find.text('Over budget'), findsOneWidget);

      // And an icon beside each, different for each state, so the badge
      // still reads in greyscale.
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('the amounts are spelled out beside the bar', (tester) async {
      await _open(tester, _api());

      expect(find.text('₹2,500.00 of ₹5,000.00'), findsOneWidget);
      expect(find.text('₹2,500.00 left'), findsOneWidget);
      // Over the limit says by how much, rather than a full bar and a colour.
      expect(find.text('₹1,200.00 of ₹1,000.00'), findsOneWidget);
      expect(find.text('₹200.00 over'), findsOneWidget);
    });

    testWidgets('a screen reader hears the state, not just the colour', (
      tester,
    ) async {
      await _open(tester, _api());

      expect(
        find.bySemanticsLabel(
          'Shopping. Over budget. ₹1,200.00 of ₹1,000.00 spent. '
          '₹200.00 over.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a bar is at its end state when animations are off', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(disableAnimations: true),
          child: _harness(_api()).app,
        ),
      );
      // Would never settle if the fill were still animating.
      await tester.pumpAndSettle();

      final bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(bars.map((bar) => bar.value), [0.5, 0.85, 1.0]);
    });
  });

  group('states', () {
    testWidgets('loading shows skeleton cards, then the budgets', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', '/categories', body: categoriesWire())
        ..respondAfter(
          'GET',
          '/budgets',
          const Duration(seconds: 1),
          body: budgetsWire(_threeStates),
        );

      await tester.pumpWidget(_harness(api).app);
      await tester.pump();
      await tester.pump();

      expect(find.bySemanticsLabel('Loading budgets'), findsOneWidget);
      expect(find.byType(BudgetCard), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(BudgetCard), findsNWidgets(3));
    });

    testWidgets('a month with nothing budgeted offers to start one', (
      tester,
    ) async {
      await _open(tester, _api(budgets: const []));

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('No budgets for September 2026'), findsOneWidget);
      expect(find.text('Set your first budget'), findsOneWidget);
    });

    testWidgets('a failure explains itself and recovers on Retry', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = _api()..failOnce('GET', '/budgets');

      await tester.pumpWidget(_harness(api).app);
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsOneWidget);
      expect(find.text('We could not load your budgets'), findsOneWidget);
      expect(find.text('The bank is unavailable.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsNothing);
      expect(find.byType(BudgetCard), findsNWidgets(3));
    });
  });

  group('rollover', () {
    testWidgets('a month with no budgets shows last month\'s, and says so', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', '/categories', body: categoriesWire())
        ..on('GET', '/budgets', times: 1, body: budgetsWire())
        ..on(
          'GET',
          '/budgets',
          times: 1,
          body: budgetsWire([
            budgetWire(
              category: 'food',
              month: '2026-08',
              limitPaise: 500000,
              spentPaise: 480000,
            ),
          ]),
        )
        ..on('GET', '/summary', body: septemberWire());

      await tester.pumpWidget(_harness(api).app);
      await tester.pumpAndSettle();

      expect(find.byType(BudgetCard), findsOneWidget);
      expect(find.text('Carried over from August 2026'), findsOneWidget);
      // August's limit against September's ₹4,500.00 of food.
      expect(find.text('₹4,500.00 of ₹5,000.00'), findsOneWidget);
      expect(find.text('Nearing limit'), findsOneWidget);
    });
  });

  testWidgets('does not overflow at textScaler 2.0 on a narrow screen', (
    tester,
  ) async {
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
    expect(find.text('On track'), findsOneWidget);

    // The cards below the fold are laid out at this size too, not only the
    // first one: a badge that wrapped badly would raise here.
    await tester.dragUntilVisible(
      find.text('Over budget'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Over budget'), findsOneWidget);
  });
}
