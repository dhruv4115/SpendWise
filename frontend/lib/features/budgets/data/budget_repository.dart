import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json_read.dart';
import '../domain/budget.dart';

/// Everything the app reads from `/budgets`. Throws [BankError] only.
class BudgetRepository {
  BudgetRepository({required Dio dio}) : _dio = dio;

  static const String budgetsPath = '/budgets';

  final Dio _dio;

  /// Every budget set for [month] (`YYYY-MM`), with what has been spent
  /// against each. Unmodifiable.
  Future<List<Budget>> fetchBudgets(String month) {
    return _dio.getObject(
      budgetsPath,
      query: {'month': month},
      parse: (json) => List<Budget>.unmodifiable(
        readObjectList(json, 'items', Budget.fromJson),
      ),
      malformedCode: 'MALFORMED_BUDGETS',
    );
  }

  /// Sets [category]'s limit for [month], creating the budget or replacing
  /// the limit it already had.
  ///
  /// The budget that comes back carries the whole month's spend, whichever
  /// day of it the limit was set on: a limit is a ceiling for the month, not
  /// from now on.
  ///
  /// [idempotencyKey] belongs to the customer's action rather than to this
  /// call, so a retry after a lost response replays the first outcome instead
  /// of setting the limit twice. A negative limit, an unknown category or a
  /// month that is not `YYYY-MM` is a 422, and arrives as a [ValidationError]
  /// whose `fieldErrors` name the field the server rejected.
  Future<Budget> upsertBudget({
    required String category,
    required String month,
    required int limitPaise,
    required String idempotencyKey,
  }) {
    return _dio.sendObject(
      'PUT',
      budgetsPath,
      body: {
        'category': category,
        'month': month,
        'limitPaise': limitPaise,
      },
      idempotencyKey: idempotencyKey,
      parse: Budget.fromJson,
      malformedCode: 'MALFORMED_BUDGET',
    );
  }
}

final Provider<BudgetRepository> budgetRepositoryProvider =
    Provider<BudgetRepository>(
  (ref) => BudgetRepository(dio: ref.watch(dioProvider)),
);
