import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/features/budgets/presentation/budget_edit_screen.dart';
import 'package:spendwise/features/budgets/widgets/budget_card.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';

import '../helpers/budgets.dart';
import '../helpers/categories.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/test_app.dart';

final DateTime _now = DateTime(2026, 9, 23, 12);

/// ₹4,200.00 of a ₹5,000.00 food budget is already gone this month.
FakeApi _api() => FakeApi()
  ..on('GET', '/categories', body: categoriesWire())
  ..on(
    'GET',
    '/budgets',
    body: budgetsWire([
      budgetWire(category: 'food', limitPaise: 500000, spentPaise: 420000),
    ]),
  );

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

Finder get _amountField => find.byType(TextFormField);

Finder get _saveButton => find.widgetWithText(FilledButton, 'Save budget');

/// Opens the food budget the way a customer does: from its card.
Future<TestHarness> _openFoodBudget(WidgetTester tester, FakeApi api) async {
  _usePhoneScreen(tester);
  final harness = _harness(api);
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();

  await tester.tap(find.byType(BudgetCard));
  await tester.pumpAndSettle();

  expect(find.byType(BudgetEditScreen), findsOneWidget);
  return harness;
}

Future<void> _enterAndSave(WidgetTester tester, String amount) async {
  await tester.enterText(_amountField, amount);
  await tester.pump();
  await tester.tap(_saveButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the current limit and this month\'s spend', (
    tester,
  ) async {
    await _openFoodBudget(tester, _api());

    // Prefilled from the budget, ready to be edited rather than retyped.
    expect(find.widgetWithText(TextFormField, '5000'), findsOneWidget);
    expect(find.text('Spent so far: ₹4,200.00'), findsOneWidget);
    expect(find.text('₹4,200.00 of ₹5,000.00'), findsOneWidget);
    expect(find.text('Nearing limit'), findsOneWidget);
  });

  testWidgets('the preview follows the amount being typed', (tester) async {
    await _openFoodBudget(tester, _api());

    // A limit below what the month has already spent is over on the spot —
    // a limit covers the whole month, not the rest of it.
    await tester.enterText(_amountField, '4000');
    await tester.pump();

    expect(find.text('₹4,200.00 of ₹4,000.00'), findsOneWidget);
    expect(find.text('Over budget'), findsOneWidget);
    expect(find.text('₹200.00 over this limit'), findsOneWidget);

    await tester.enterText(_amountField, '10000');
    await tester.pump();

    expect(find.text('On track'), findsOneWidget);
    expect(find.text('₹5,800.00 left this month'), findsOneWidget);
  });

  testWidgets('a negative amount is stopped before it reaches the bank', (
    tester,
  ) async {
    final api = _api();
    await _openFoodBudget(tester, api);

    await _enterAndSave(tester, '-500');

    expect(find.text('A budget cannot be negative.'), findsOneWidget);
    // Nothing was sent: the rule is the client's as well as the server's.
    expect(api.requestsFor('PUT', '/budgets'), isEmpty);
    expect(find.byType(BudgetEditScreen), findsOneWidget);
  });

  testWidgets('a 422 is shown under the field the server named', (
    tester,
  ) async {
    const serverMessage = 'Your bank caps this category at ₹50,000.';
    final api = _api()
      ..respondError(
        'PUT',
        '/budgets',
        status: 422,
        code: 'VALIDATION_FAILED',
        message: 'We could not save that budget.',
        details: const {'limitPaise': serverMessage},
      );
    await _openFoodBudget(tester, api);

    await _enterAndSave(tester, '60000');

    expect(api.requestsFor('PUT', '/budgets'), hasLength(1));
    expect(find.text(serverMessage), findsOneWidget);
    // Under the field, not in a banner the customer has to map back onto it.
    expect(
      find.text('Budget not saved. We could not save that budget.'),
      findsNothing,
    );
    expect(find.byType(BudgetEditScreen), findsOneWidget);

    // A different amount is a different question, so the objection goes.
    await tester.enterText(_amountField, '40000');
    // Settled, so the message has finished fading out rather than merely
    // having been cleared from the decoration.
    await tester.pumpAndSettle();

    expect(find.text(serverMessage), findsNothing);
  });

  testWidgets('retrying a failed Save reuses the one idempotency key', (
    tester,
  ) async {
    final api = _api()
      ..failOnce('PUT', '/budgets')
      ..on(
        'PUT',
        '/budgets',
        body: budgetWire(
          category: 'food',
          limitPaise: 600000,
          spentPaise: 420000,
        ),
      );
    await _openFoodBudget(tester, api);

    await _enterAndSave(tester, '6000');

    expect(
      find.text('Budget not saved. The bank is unavailable.'),
      findsOneWidget,
    );
    expect(find.byType(BudgetEditScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();

    // Saved, and confirmed on the list the customer lands back on.
    expect(find.byType(BudgetEditScreen), findsNothing);
    expect(
      find.text(
        'Food & Dining budget set to ₹6,000.00 for September 2026.',
      ),
      findsOneWidget,
    );

    final sent = api.requestsFor('PUT', '/budgets');
    expect(sent, hasLength(2), reason: 'the first attempt and its retry');
    expect(sent.first.idempotencyKey, isNotNull);
    expect(
      sent.last.idempotencyKey,
      sent.first.idempotencyKey,
      reason: 'a retry replays the change rather than making a second one',
    );
    expect(sent.last.jsonBody, {
      'category': 'food',
      'month': '2026-09',
      'limitPaise': 600000,
    });
  });
}
