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
}

final Provider<BudgetRepository> budgetRepositoryProvider =
    Provider<BudgetRepository>(
  (ref) => BudgetRepository(dio: ref.watch(dioProvider)),
);
