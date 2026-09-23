import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/errors/bank_error.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/budgets/data/budget_risk.dart';
import 'package:spendwise/features/budgets/state/budget_edit_controller.dart';
import 'package:spendwise/features/budgets/state/budgets_provider.dart';

import '../helpers/budgets.dart';
import '../helpers/container.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/summaries.dart';

const String _month = '2026-09';
const String _previousMonth = '2026-08';

/// September, as `GET /summary` sends it: ₹4,500.00 of food, ₹1,200.00 of
/// transport, and nothing at all in education.
Map<String, Object?> _september() => septemberWire();

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

Future<List<BudgetView>> _load(ProviderContainer container) {
  readAndKeepAlive(container, budgetsProvider(_month));
  return container.read(budgetsProvider(_month).future);
}

void main() {
  group('budgetsProvider', () {
    test('shows the month its own budgets, and asks for nothing else',
        () async {
      final api = FakeApi()
        ..on(
          'GET',
          '/budgets',
          body: budgetsWire([
            budgetWire(category: 'food', limitPaise: 500000, spentPaise: 450000)
          ]),
        );
      final container = _container(api);

      final budgets = await _load(container);

      expect(budgets, hasLength(1));
      final food = budgets.single;
      expect(food.category, 'food');
      expect(food.limitPaise, 500000);
      expect(food.spentPaise, 450000);
      expect(food.isRolledOver, isFalse);
      expect(food.risk, BudgetRisk.warning);
      expect(food.ratio, 0.9);
      expect(food.remainingPaise, 50000);
      // A month with budgets of its own needs neither last month's nor the
      // summary: the rows carry their own spend.
      expect(api.requestsFor('GET', '/budgets'), hasLength(1));
      expect(api.requestsFor('GET', '/summary'), isEmpty);
      expect(api.requestsFor('GET', '/budgets').single.query, {
        'month': _month,
      });
    });

    test('rolls last month\'s limits over into a month that has none',
        () async {
      final api = FakeApi()
        // September first: nothing budgeted yet.
        ..on('GET', '/budgets', times: 1, body: budgetsWire())
        // Then August, which is where the limits come from.
        ..on(
          'GET',
          '/budgets',
          times: 1,
          body: budgetsWire([
            budgetWire(
              category: 'food',
              month: _previousMonth,
              limitPaise: 500000,
              spentPaise: 480000,
            ),
            budgetWire(
              category: 'education',
              month: _previousMonth,
              limitPaise: 200000,
              spentPaise: 150000,
            ),
          ]),
        )
        ..on('GET', '/summary', body: _september());
      final container = _container(api);

      final budgets = await _load(container);

      expect(
        api.requestsFor('GET', '/budgets').map((r) => r.query['month']),
        [_month, _previousMonth],
      );

      final food = budgets.forCategory('food')!;
      expect(food.limitPaise, 500000, reason: "August's limit");
      expect(food.spentPaise, 450000, reason: "September's spend");
      expect(food.isRolledOver, isTrue);
      expect(food.rolledOverFrom, _previousMonth);
      expect(food.risk, BudgetRisk.warning);

      // A category nothing has been spent in this month starts from zero,
      // not from what it came to in August.
      final education = budgets.forCategory('education')!;
      expect(education.limitPaise, 200000);
      expect(education.spentPaise, 0);
      expect(education.risk, BudgetRisk.safe);
    });

    test('is empty when neither this month nor last has a budget', () async {
      final api = FakeApi()..on('GET', '/budgets', body: budgetsWire());
      final container = _container(api);

      expect(await _load(container), isEmpty);
      // Nothing to seed a view with, so the summary is never asked for.
      expect(api.requestsFor('GET', '/summary'), isEmpty);
    });

    test('a failed summary fails the month rather than showing no spend',
        () async {
      final api = FakeApi()
        ..on('GET', '/budgets', times: 1, body: budgetsWire())
        ..on(
          'GET',
          '/budgets',
          times: 1,
          body: budgetsWire([
            budgetWire(
              category: 'food',
              month: _previousMonth,
              limitPaise: 500000,
            ),
          ]),
        )
        ..respondError(
          'GET',
          '/summary',
          status: 503,
          code: 'UPSTREAM_UNAVAILABLE',
          message: 'The bank is unavailable.',
        );
      final container = _container(api);

      // A carried-over row with its spend quietly zeroed would read "On
      // track" to a customer who is over their limit.
      await expectLater(_load(container), throwsA(isA<ServerError>()));
      expect(
        container.read(budgetsProvider(_month)),
        isA<AsyncError<List<BudgetView>>>(),
      );
    });

    test('a malformed budget is a BankError, not a FormatException', () async {
      final api = FakeApi()
        ..on('GET', '/budgets', body: {
          'items': [
            {
              'category': 'food',
              'month': _month,
              'limitPaise': 5000.5,
              'spentPaise': 0,
            },
          ],
        });
      final container = _container(api);

      await expectLater(
        _load(container),
        throwsA(
          isA<UnknownError>()
              .having((e) => e.code, 'code', 'MALFORMED_BUDGETS'),
        ),
      );
    });
  });

  group('budgetDraftProvider', () {
    test('a budget set mid-month starts from the whole month\'s spend',
        () async {
      // Food has no budget on the 20th, but ₹4,500.00 has already gone out
      // of it this month. The draft has to carry all of it — a limit set
      // today is a ceiling for September, not for the rest of September.
      final api = FakeApi()
        ..on(
          'GET',
          '/budgets',
          body: budgetsWire([
            budgetWire(
              category: 'transport',
              limitPaise: 200000,
              spentPaise: 120000,
            ),
          ]),
        )
        ..on('GET', '/summary', body: _september());
      final container = _container(api);
      const target = BudgetTarget(month: _month, category: 'food');

      readAndKeepAlive(container, budgetDraftProvider(target));
      final draft = await container.read(budgetDraftProvider(target).future);

      expect(draft.category, 'food');
      expect(draft.limitPaise, 0, reason: 'nothing budgeted yet');
      expect(draft.spentPaise, 450000, reason: "the whole month's food spend");
      expect(draft.isRolledOver, isFalse);
      // So the live preview of a ₹5,000.00 limit already says "nearing".
      expect(draft.copyWith(limitPaise: 500000).risk, BudgetRisk.warning);
      expect(draft.copyWith(limitPaise: 400000).risk, BudgetRisk.over);
    });

    test('an existing budget is the draft, carried-over flag and all',
        () async {
      final api = FakeApi()
        ..on('GET', '/budgets', times: 1, body: budgetsWire())
        ..on(
          'GET',
          '/budgets',
          times: 1,
          body: budgetsWire([
            budgetWire(
              category: 'food',
              month: _previousMonth,
              limitPaise: 500000,
            ),
          ]),
        )
        ..on('GET', '/summary', body: _september());
      final container = _container(api);
      const target = BudgetTarget(month: _month, category: 'food');

      readAndKeepAlive(container, budgetDraftProvider(target));
      final draft = await container.read(budgetDraftProvider(target).future);

      expect(draft.limitPaise, 500000);
      expect(draft.spentPaise, 450000);
      expect(draft.rolledOverFrom, _previousMonth);
    });
  });

  group('BudgetEditController', () {
    test('saving a limit sends it once and re-reads the month', () async {
      final api = FakeApi()
        ..on(
          'GET',
          '/budgets',
          times: 1,
          body: budgetsWire([
            budgetWire(category: 'food', limitPaise: 500000, spentPaise: 450000)
          ]),
        )
        ..on(
          'PUT',
          '/budgets',
          body: budgetWire(
            category: 'food',
            limitPaise: 600000,
            spentPaise: 450000,
          ),
        )
        ..on(
          'GET',
          '/budgets',
          body: budgetsWire([
            budgetWire(category: 'food', limitPaise: 600000, spentPaise: 450000)
          ]),
        );
      final container = _container(api);
      const target = BudgetTarget(month: _month, category: 'food');

      final budgets = await _load(container);
      expect(budgets.single.limitPaise, 500000);

      readAndKeepAlive(container, budgetEditControllerProvider(target));
      final outcome = await container
          .read(budgetEditControllerProvider(target).notifier)
          .save(600000);

      expect(outcome, isA<BudgetSaved>());
      expect((outcome as BudgetSaved).budget.limitPaise, 600000);

      final sent = api.requestsFor('PUT', '/budgets').single;
      expect(sent.jsonBody, {
        'category': 'food',
        'month': _month,
        'limitPaise': 600000,
      });
      expect(sent.idempotencyKey, isNotNull);

      // The list behind the screen is re-read, so it shows the new limit.
      final refreshed = await container.read(budgetsProvider(_month).future);
      expect(refreshed.single.limitPaise, 600000);
      expect(api.requestsFor('GET', '/budgets'), hasLength(2));
    });

    test('the key is fixed when the screen opens and survives a failure',
        () async {
      final api = FakeApi()
        ..on('GET', '/budgets', body: budgetsWire())
        ..failOnce('PUT', '/budgets')
        ..on(
          'PUT',
          '/budgets',
          body: budgetWire(category: 'food', limitPaise: 600000),
        );
      final container = _container(api);
      const target = BudgetTarget(month: _month, category: 'food');

      final opened = readAndKeepAlive(
        container,
        budgetEditControllerProvider(target),
      );
      final keyAtOpen = opened.requireValue.idempotencyKey;
      expect(keyAtOpen, isNotEmpty);

      final controller =
          container.read(budgetEditControllerProvider(target).notifier);
      expect(await controller.save(600000), isA<BudgetSaveFailed>());
      expect(await controller.save(600000), isA<BudgetSaved>());

      final sent = api.requestsFor('PUT', '/budgets');
      expect(sent, hasLength(2));
      expect(sent.first.idempotencyKey, keyAtOpen);
      expect(sent.last.idempotencyKey, keyAtOpen);
    });

    test('a 422 lands on the field the server named', () async {
      final api = FakeApi()
        ..on(
          'GET',
          '/budgets',
          body: budgetsWire([
            budgetWire(category: 'food', limitPaise: 500000, spentPaise: 450000)
          ]),
        )
        ..respondError(
          'PUT',
          '/budgets',
          status: 422,
          code: 'VALIDATION_FAILED',
          message: 'We could not save that budget.',
          details: const {'limitPaise': 'A budget cannot be negative.'},
        );
      final container = _container(api);
      const target = BudgetTarget(month: _month, category: 'food');

      await _load(container);
      readAndKeepAlive(container, budgetEditControllerProvider(target));
      final outcome = await container
          .read(budgetEditControllerProvider(target).notifier)
          .save(-1);

      expect(outcome, isA<BudgetSaveFailed>());
      expect((outcome as BudgetSaveFailed).error, isA<ValidationError>());

      final state =
          container.read(budgetEditControllerProvider(target)).valueOrNull!;
      expect(state.limitError, 'A budget cannot be negative.');
      expect(state.rejectedLimitPaise, -1);
      // The month is not re-read for a change the server refused.
      expect(api.requestsFor('GET', '/budgets'), hasLength(1));
    });
  });
}
