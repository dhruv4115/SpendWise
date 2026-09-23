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

  group('TransactionRepository.recategorise', () {
    test('PATCHes with the caller\'s key and parses the result', () async {
      final api = FakeApi()
        ..on(
          'PATCH',
          '/transactions/txn_1',
          body: {
            'updated': txnWire(id: 'txn_1', category: 'groceries'),
            'changedIds': ['txn_1', 'txn_2'],
            'undoToken': 'undo-1',
          },
        );

      final result = await _repository(api).recategorise(
        id: 'txn_1',
        category: 'groceries',
        applyToMerchant: true,
        idempotencyKey: 'key-1',
      );

      expect(result.updated.category, 'groceries');
      expect(result.updated.at.isUtc, isFalse);
      expect(result.changedIds, ['txn_1', 'txn_2']);
      expect(result.undoToken, 'undo-1');
      expect(result.toString(), isNot(contains('undo-1')));

      final request = api.requests.single;
      expect(request.method, 'PATCH');
      expect(request.idempotencyKey, 'key-1');
      expect(
          request.jsonBody, {'category': 'groceries', 'applyToMerchant': true});
    });

    test('maps a 422 to ValidationError with the field reason', () async {
      final api = FakeApi()
        ..respondError(
          'PATCH',
          '/transactions/txn_1',
          status: 422,
          code: 'VALIDATION_FAILED',
          message: 'That category does not exist.',
          details: {'category': 'Unknown category.'},
        );

      await expectLater(
        _repository(api).recategorise(
          id: 'txn_1',
          category: 'crypto',
          applyToMerchant: false,
          idempotencyKey: 'key-1',
        ),
        throwsA(
          isA<ValidationError>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.fieldErrors, 'fieldErrors',
                  {'category': 'Unknown category.'}),
        ),
      );
    });

    test('a 200 with a malformed body is an UnknownError', () async {
      final api = FakeApi()
        ..on('PATCH', '/transactions/txn_1', body: {
          'updated': txnWire(id: 'txn_1'),
          'changedIds': 'txn_1',
          'undoToken': 'undo-1',
        });

      await expectLater(
        _repository(api).recategorise(
          id: 'txn_1',
          category: 'food',
          applyToMerchant: false,
          idempotencyKey: 'key-1',
        ),
        throwsA(
          isA<UnknownError>()
              .having((e) => e.code, 'code', 'MALFORMED_RECATEGORISE_RESULT'),
        ),
      );
    });
  });

  group('TransactionRepository.undo', () {
    test('POSTs the token with the caller\'s key and returns the ids',
        () async {
      final api = FakeApi()
        ..on('POST', '/transactions/undo', body: {
          'restoredIds': ['txn_1', 'txn_2'],
        });

      final restored =
          await _repository(api).undo('undo-1', idempotencyKey: 'key-2');

      expect(restored, ['txn_1', 'txn_2']);
      final request = api.requests.single;
      expect(request.idempotencyKey, 'key-2');
      expect(request.jsonBody, {'undoToken': 'undo-1'});
    });

    test('an already-redeemed token is a NotFoundError', () async {
      final api = FakeApi()
        ..respondError(
          'POST',
          '/transactions/undo',
          status: 404,
          code: 'UNDO_TOKEN_INVALID',
        );

      await expectLater(
        _repository(api).undo('undo-1', idempotencyKey: 'key-2'),
        throwsA(isA<NotFoundError>()),
      );
    });
  });
}
