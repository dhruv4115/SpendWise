import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/transactions/domain/transaction_filter.dart';
import 'package:spendwise/features/transactions/presentation/filters_sheet.dart';
import 'package:spendwise/features/transactions/state/filter_provider.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';

import '../helpers/categories.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/test_app.dart';

/// Midday on 23 Sep 2026: the picker's last selectable day.
final DateTime _now = DateTime(2026, 9, 23, 12);

const String _maxBelowMin = 'The maximum must be at least the minimum.';

/// What the sheet handed back, and whether it has closed at all — a null
/// result alone cannot tell "dismissed" from "still open".
class _Outcome {
  bool closed = false;
  TransactionFilter? result;
}

FakeApi _api() => FakeApi()..on('GET', '/categories', body: categoriesWire());

/// A page with one button that opens the sheet the way the feed does, and
/// records what comes back. Nothing here applies the result.
Widget _host(
  FakeApi api,
  _Outcome outcome, {
  TransactionFilter initial = TransactionFilter.none,
}) {
  return testApp(
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              final result = await FiltersSheet.show(
                context,
                initial: initial,
                month: '2026-09',
              );
              outcome
                ..closed = true
                ..result = result;
            },
            child: const Text('Open filters'),
          ),
        ),
      ),
    ),
    overrides: [
      sessionStoreProvider.overrideWithValue(
        FakeSessionStore(session: testSession),
      ),
      httpClientAdapterProvider.overrideWithValue(api),
      clockProvider.overrideWithValue(() => _now),
    ],
  );
}

void _usePhoneScreen(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open filters'));
  await tester.pumpAndSettle();
  expect(find.byType(FiltersSheet), findsOneWidget);
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

ChoiceChip _chip(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

void main() {
  group('validation', () {
    testWidgets('a maximum below the minimum is an error, and Apply stays', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final outcome = _Outcome();
      await tester.pumpWidget(_host(_api(), outcome));
      await _open(tester);

      await tester.enterText(_field('Minimum'), '1000');
      await tester.enterText(_field('Maximum'), '500');
      expect(find.text(_maxBelowMin), findsNothing,
          reason: 'no error while still typing');

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text(_maxBelowMin), findsOneWidget);
      expect(find.byType(FiltersSheet), findsOneWidget, reason: 'not popped');
      expect(outcome.closed, isFalse);

      // Once shown, the error follows the typing and clears when fixed.
      await tester.enterText(_field('Maximum'), '1,500');
      await tester.pump();
      expect(find.text(_maxBelowMin), findsNothing);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(
        outcome.result,
        const TransactionFilter(minPaise: 100000, maxPaise: 150000),
      );
    });

    testWidgets('an amount that is not one is an error too', (tester) async {
      _usePhoneScreen(tester);
      final outcome = _Outcome();
      await tester.pumpWidget(_host(_api(), outcome));
      await _open(tester);

      await tester.enterText(_field('Minimum'), '12.345');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter an amount in rupees, for example 500 or 499.50.'),
        findsOneWidget,
      );
      expect(outcome.closed, isFalse);
    });
  });

  group('the result comes back through pop', () {
    testWidgets('Apply pops the exact filter, search carried through', (
      tester,
    ) async {
      // Wider than a phone for Flutter's own date range picker: the test font
      // draws every glyph a full em wide, and its header ("Sep 5 – Sep 12")
      // would overflow at phone width in a way no real font does.
      _usePhoneScreen(tester, size: const Size(600, 900));
      final outcome = _Outcome();
      await tester.pumpWidget(
        _host(_api(), outcome, initial: const TransactionFilter(query: 'big')),
      );
      await _open(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Groceries'));
      await tester.pump();
      expect(_chip(tester, 'Groceries').selected, isTrue);
      expect(_chip(tester, 'All categories').selected, isFalse);

      await tester.enterText(_field('Minimum'), '250.5');
      await tester.enterText(_field('Maximum'), '₹1,000');

      // Below the fold, under the buttons: scroll to it as a customer would.
      await tester.ensureVisible(find.text('Any date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any date'));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      await tester.tap(find.text('5'));
      await tester.pump();
      await tester.tap(find.text('12'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('5 Sep – 12 Sep'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.byType(FiltersSheet), findsNothing);
      expect(outcome.closed, isTrue);
      expect(
        outcome.result,
        TransactionFilter(
          category: 'groceries',
          query: 'big',
          minPaise: 25050,
          maxPaise: 100000,
          from: DateTime(2026, 9, 5),
          // Inclusive of the whole last day.
          to: DateTime(2026, 9, 12, 23, 59, 59, 999),
        ),
      );

      // The sheet only returned it: the app-wide filter is untouched.
      final container = ProviderScope.containerOf(
        tester.element(find.text('Open filters')),
      );
      expect(container.read(filterStateNotifier), TransactionFilter.none);
    });

    testWidgets('it opens on the filter it was given, and returns it intact', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final initial = TransactionFilter(
        category: 'food',
        query: 'swiggy',
        minPaise: 50000,
        maxPaise: 125050,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 10, 23, 59, 59, 999),
      );
      final outcome = _Outcome();
      await tester.pumpWidget(_host(_api(), outcome, initial: initial));
      await _open(tester);

      expect(_chip(tester, 'Food & Dining').selected, isTrue);
      expect(find.widgetWithText(TextFormField, '500'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '1250.50'), findsOneWidget);
      expect(find.text('1 Sep – 10 Sep'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(outcome.result, initial,
          reason: 'an equal filter is the same feed: no refetch');
    });

    testWidgets('Clear all empties the draft; only Apply commits it', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final outcome = _Outcome();
      await tester.pumpWidget(
        _host(
          _api(),
          outcome,
          initial: TransactionFilter(
            category: 'food',
            query: 'swiggy',
            minPaise: 50000,
            from: DateTime(2026, 9, 1),
            to: DateTime(2026, 9, 10, 23, 59, 59, 999),
          ),
        ),
      );
      await _open(tester);

      await tester.tap(find.text('Clear all'));
      await tester.pump();

      expect(find.byType(FiltersSheet), findsOneWidget);
      expect(outcome.closed, isFalse);
      expect(_chip(tester, 'All categories').selected, isTrue);
      expect(find.text('Any date'), findsOneWidget);
      expect(find.byTooltip('Clear dates'), findsNothing);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // The search is not the sheet's to clear.
      expect(outcome.result, const TransactionFilter(query: 'swiggy'));
    });

    testWidgets('dismissing returns null', (tester) async {
      _usePhoneScreen(tester);
      final outcome = _Outcome();
      await tester.pumpWidget(
        _host(_api(), outcome, initial: const TransactionFilter(query: 'x')),
      );
      await _open(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Travel'));

      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      expect(find.byType(FiltersSheet), findsNothing);
      expect(outcome.closed, isTrue);
      expect(outcome.result, isNull);
    });
  });

  group('categories', () {
    testWidgets('a failed list says so, retries, and the rest still works', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = _api()..failOnce('GET', '/categories');
      final outcome = _Outcome();
      await tester.pumpWidget(_host(api, outcome));
      await _open(tester);

      expect(find.textContaining('We could not load the categories.'),
          findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Groceries'), findsOneWidget);
      expect(api.requestsFor('GET', '/categories'), hasLength(2));
    });
  });

  group('at textScaler 2.0', () {
    testWidgets('nothing overflows; the middle scrolls and Apply stays put', (
      tester,
    ) async {
      _usePhoneScreen(tester, size: const Size(360, 720));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final outcome = _Outcome();
      await tester.pumpWidget(_host(_api(), outcome));
      await _open(tester);

      expect(
        MediaQuery.textScalerOf(tester.element(find.text('Apply'))).scale(10),
        20,
        reason: 'the test must really be running at 2.0',
      );
      expect(tester.takeException(), isNull);

      final applyTop = tester.getTopLeft(find.text('Apply')).dy;
      await tester.scrollUntilVisible(
        find.text('Any date'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(FiltersSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('Apply')).dy, applyTop);

      await tester.enterText(_field('Minimum'), '900');
      await tester.enterText(_field('Maximum'), '100');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // The long error wraps under a full-width field instead of clipping.
      expect(find.text(_maxBelowMin), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
