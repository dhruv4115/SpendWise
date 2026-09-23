import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json_read.dart';
import '../domain/recategorise_result.dart';
import '../domain/transaction.dart';
import '../domain/transaction_filter.dart';
import '../domain/transaction_page.dart';

/// Everything the app does with `/transactions`.
///
/// JSON becomes domain objects here and nowhere else. Throws [BankError] and
/// nothing else: a [DioException] is mapped at this border, and a 200 whose
/// body cannot be parsed becomes an [UnknownError] rather than leaking a
/// [FormatException] into a widget.
class TransactionRepository {
  TransactionRepository({required Dio dio}) : _dio = dio;

  static const String transactionsPath = '/transactions';
  static const String undoPath = '$transactionsPath/undo';

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
    return _dio.getObject(
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
    return _dio.getObject(
      _itemPath(id),
      parse: Transaction.fromJson,
      malformedCode: 'MALFORMED_TRANSACTION',
    );
  }

  /// Moves [id] to [category] — and with [applyToMerchant], every transaction
  /// from the same merchant: past ones immediately, future ones through the
  /// rule the server keeps for that merchant.
  ///
  /// [idempotencyKey] belongs to the customer's action, not to this call. A
  /// category the server does not know is a [ValidationError] (422).
  Future<RecategoriseResult> recategorise({
    required String id,
    required String category,
    required bool applyToMerchant,
    required String idempotencyKey,
  }) {
    return _dio.sendObject(
      'PATCH',
      _itemPath(id),
      body: {'category': category, 'applyToMerchant': applyToMerchant},
      idempotencyKey: idempotencyKey,
      parse: RecategoriseResult.fromJson,
      malformedCode: 'MALFORMED_RECATEGORISE_RESULT',
    );
  }

  /// Reverses the change [undoToken] was issued for, merchant rule included.
  /// Returns the ids the server put back.
  ///
  /// A token that has already been redeemed is a [NotFoundError].
  Future<List<String>> undo(
    String undoToken, {
    required String idempotencyKey,
  }) {
    return _dio.sendObject(
      'POST',
      undoPath,
      body: {'undoToken': undoToken},
      idempotencyKey: idempotencyKey,
      parse: (json) => readStringList(json, 'restoredIds'),
      malformedCode: 'MALFORMED_UNDO_RESULT',
    );
  }

  static String _itemPath(String id) =>
      '$transactionsPath/${Uri.encodeComponent(id)}';
}

final Provider<TransactionRepository> transactionRepositoryProvider =
    Provider<TransactionRepository>(
  (ref) => TransactionRepository(dio: ref.watch(dioProvider)),
);
