import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/errors/bank_error.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/features/transactions/data/transaction_repository.dart';
import 'package:spendwise/features/transactions/domain/transaction_filter.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/transactions.dart';

TransactionRepository _repository(FakeApi api) {
  final dio = buildApiClient(
    store: FakeSessionStore(session: testSession),
    onUnauthorised: () async {},
    log: (_) {},
  )..httpClientAdapter = api;
  return TransactionRepository(dio: dio);
}

void main() {
  group('TransactionRepository.fetchPage', () {
    test('sends month, filter, cursor and limit, and parses the page',
        () async {
      final api = FakeApi()
        ..on(
          'GET',
          '/transactions',
          body: pageWire([txnWire(id: 'txn_1')], nextCursor: 'c3'),
        );

      final page = await _repository(api).fetchPage(
        month: '2026-09',
        filter: const TransactionFilter(category: 'food', minPaise: 500),
        cursor: 'c2',
        limit: 25,
      );

      expect(page.items.single.id, 'txn_1');
      expect(page.items.single.at.isUtc, isFalse);
      expect(page.nextCursor, 'c3');
      expect(api.requests.single.query, {
        'month': '2026-09',
        'category': 'food',
        'minPaise': '500',
        'cursor': 'c2',
        'limit': '25',
      });
    });

    test('an empty cursor means the last page, not page one again', () async {
      final api = FakeApi()
        ..on('GET', '/transactions', body: pageWire([], nextCursor: ''));

      final page = await _repository(api).fetchPage(month: '2026-09');

      expect(page.nextCursor, isNull);
      expect(page.isLast, isTrue);
    });

    test('maps a 422 to ValidationError', () async {
      final api = FakeApi()
        ..respondError(
          'GET',
          '/transactions',
          status: 422,
          code: 'VALIDATION_FAILED',
          message: 'That month is not valid.',
        );

      await expectLater(
        _repository(api).fetchPage(month: '2026-13'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a body that is not a page becomes UnknownError', () async {
      final api = FakeApi()..on('GET', '/transactions', body: ['not', 'a map']);

      await expectLater(
        _repository(api).fetchPage(month: '2026-09'),
        throwsA(
          isA<UnknownError>().having(
            (e) => e.code,
            'code',
            'MALFORMED_TRANSACTION_PAGE',
          ),
        ),
      );
    });
  });

  group('TransactionRepository.fetchOne', () {
    test('encodes the id into the path and parses the transaction', () async {
      final api = FakeApi()
        ..on(
          'GET',
          '/transactions/txn%2F1',
          body: txnWire(id: 'txn/1', amountPaise: 20000),
        );

      final txn = await _repository(api).fetchOne('txn/1');

      expect(txn.id, 'txn/1');
      expect(txn.isRefund, isTrue);
    });

    test('maps a 404 to NotFoundError', () async {
      final api = FakeApi()
        ..respondError(
          'GET',
          '/transactions/txn_missing',
          status: 404,
          code: 'NOT_FOUND',
        );

      await expectLater(
        _repository(api).fetchOne('txn_missing'),
        throwsA(isA<NotFoundError>()),
      );
    });
  });
}
