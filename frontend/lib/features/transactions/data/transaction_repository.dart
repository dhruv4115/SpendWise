import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/error_mapper.dart';
import '../domain/transaction.dart';
import '../domain/transaction_filter.dart';
import '../domain/transaction_page.dart';

/// Everything the app reads from `/transactions`.
///
/// JSON becomes domain objects here and nowhere else. Throws [BankError] and
/// nothing else: a [DioException] is mapped at this border, and a 200 whose
/// body cannot be parsed becomes an [UnknownError] rather than leaking a
/// [FormatException] into a widget.
class TransactionRepository {
  TransactionRepository({required Dio dio}) : _dio = dio;

  static const String transactionsPath = '/transactions';

  /// The server's default, and its maximum is 200.
  static const int defaultPageSize = 50;

  final Dio _dio;

  /// One page of [month] (`YYYY-MM`), newest first.
  ///
  /// [cursor] is the previous page's `nextCursor`; leave it null for page one.
  Future<TransactionPage> fetchPage({
    required String month,
    TransactionFilter filter = TransactionFilter.none,
    String? cursor,
    int limit = defaultPageSize,
  }) {
    return _getObject(
      transactionsPath,
      query: {
        'month': month,
        ...filter.toQueryParameters(),
        if (cursor != null) 'cursor': cursor,
        'limit': '$limit',
      },
      parse: TransactionPage.fromJson,
      malformedCode: 'MALFORMED_TRANSACTION_PAGE',
    );
  }

  /// A single transaction. A 404 arrives as [NotFoundError].
  Future<Transaction> fetchOne(String id) {
    return _getObject(
      '$transactionsPath/${Uri.encodeComponent(id)}',
      parse: Transaction.fromJson,
      malformedCode: 'MALFORMED_TRANSACTION',
    );
  }

  Future<T> _getObject<T>(
    String path, {
    Map<String, String>? query,
    required T Function(Map<String, Object?> json) parse,
    required String malformedCode,
  }) async {
    final Object? data;
    try {
      final response = await _dio.get<Object?>(path, queryParameters: query);
      data = response.data;
    } on DioException catch (error) {
      throw mapDioException(error);
    }

    if (data is! Map) throw UnknownError(code: malformedCode);
    try {
      return parse(Map<String, Object?>.from(data));
    } on FormatException {
      // The server said 200 and sent something unusable. The parse detail
      // names fields and values, so it stays out of the customer's banner.
      throw UnknownError(code: malformedCode);
    }
  }
}

final Provider<TransactionRepository> transactionRepositoryProvider =
    Provider<TransactionRepository>(
  (ref) => TransactionRepository(dio: ref.watch(dioProvider)),
);
