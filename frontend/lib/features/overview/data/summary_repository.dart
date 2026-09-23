import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/network/api_client.dart';
import '../domain/month_summary.dart';

/// Everything the app reads from `/summary`. Throws [BankError] only.
class SummaryRepository {
  SummaryRepository({required Dio dio}) : _dio = dio;

  static const String summaryPath = '/summary';

  final Dio _dio;

  /// The server's roll-up of [month] (`YYYY-MM`).
  Future<MonthSummary> fetchSummary(String month) {
    return _dio.getObject(
      summaryPath,
      query: {'month': month},
      parse: MonthSummary.fromJson,
      malformedCode: 'MALFORMED_SUMMARY',
    );
  }
}

final Provider<SummaryRepository> summaryRepositoryProvider =
    Provider<SummaryRepository>(
  (ref) => SummaryRepository(dio: ref.watch(dioProvider)),
);
