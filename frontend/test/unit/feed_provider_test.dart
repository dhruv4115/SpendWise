import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/errors/bank_error.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/transactions/domain/transaction_filter.dart';
import 'package:spendwise/features/transactions/state/feed_provider.dart';

import '../helpers/container.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/transactions.dart';

const String _path = '/transactions';
const FeedKey _key = FeedKey(month: '2026-09');

/// The production feed, repository and Dio client, on a fake transport.
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

/// Keeps the auto-disposing feed alive and waits for page one.
Future<FeedState> _loadFirstPage(ProviderContainer container) {
  readAndKeepAlive(container, feedProvider(_key));
  return container.read(feedProvider(_key).future);
}

FeedState _state(ProviderContainer container) =>
    container.read(feedProvider(_key)).requireValue;

FeedNotifier _notifier(ProviderContainer container) =>
    container.read(feedProvider(_key).notifier);

List<String> _ids(FeedState state) => [for (final t in state.items) t.id];

void main() {
  group('FeedNotifier.build', () {
    test('loads page one of the month, with no cursor', () async {
      final api = FakeApi()
        ..on(
          'GET',
          _path,
          body: pageWire(
            [txnWire(id: 'txn_1'), txnWire(id: 'txn_2')],
            nextCursor: 'c2',
          ),
        );
      final container = _container(api);

      final state = await _loadFirstPage(container);

      expect(_ids(state), ['txn_1', 'txn_2']);
      expect(state.nextCursor, 'c2');
      expect(state.hasMore, isTrue);
      expect(state.isLoadingMore, isFalse);
      expect(state.loadMoreError, isNull);

      final request = api.requestsFor('GET', _path).single;
      expect(request.query['month'], '2026-09');
      expect(request.query['limit'], '${FeedNotifier.pageSize}');
      expect(request.query.containsKey('cursor'), isFalse);
      expect(request.authorization, 'Bearer ${testSession.token}');
    });

    test('sends the filter along with the month', () async {
      final api = FakeApi()..on('GET', _path, body: pageWire([]));
      final container = _container(api);
      const key = FeedKey(
        month: '2026-08',
        filter: TransactionFilter(category: 'food', query: ' swig '),
      );
      readAndKeepAlive(container, feedProvider(key));

      await container.read(feedProvider(key).future);

      final query = api.requestsFor('GET', _path).single.query;
      expect(query['month'], '2026-08');
      expect(query['category'], 'food');
      expect(query['q'], 'swig');
    });

    test('equal keys share one feed and one request', () async {
      final api = FakeApi()..on('GET', _path, body: pageWire([txnWire()]));
      final container = _container(api);
      readAndKeepAlive(container, feedProvider(_key));
      const sameKey = FeedKey(month: '2026-09', filter: TransactionFilter());
      readAndKeepAlive(container, feedProvider(sameKey));

      await container.read(feedProvider(sameKey).future);

      expect(api.requestsFor('GET', _path), hasLength(1));
    });

    test('a BankError surfaces as AsyncError', () async {
      final api = FakeApi()
        ..respondError(
          'GET',
          _path,
          status: 503,
          code: 'UPSTREAM_UNAVAILABLE',
          message: 'The bank is unavailable.',
        );
      final container = _container(api);
      readAndKeepAlive(container, feedProvider(_key));

      await expectLater(
        container.read(feedProvider(_key).future),
        throwsA(isA<ServerError>()),
      );

      final value = container.read(feedProvider(_key));
      expect(value, isA<AsyncError<FeedState>>());
      expect(value.error, isA<ServerError>());
      expect(
          (value.error! as BankError).userMessage, 'The bank is unavailable.');
    });

    test('a malformed page surfaces as a BankError, not a FormatException',
        () async {
      final api = FakeApi()
        ..on('GET', _path, body: {
          'items': [
            {'id': 'txn_1', 'amountPaise': 12.5},
          ],
          'nextCursor': null,
        });
      final container = _container(api);
      readAndKeepAlive(container, feedProvider(_key));

      await expectLater(
        container.read(feedProvider(_key).future),
        throwsA(isA<UnknownError>()),
      );
    });
  });

  group('FeedNotifier.loadMore', () {
    test('appends the next page and stops at a null cursor', () async {
      final api = FakeApi()
        ..on('GET', _path,
            times: 1, body: pageWire(spendsWire(2), nextCursor: 'c2'))
        ..on(
          'GET',
          _path,
          times: 1,
          body: pageWire(spendsWire(2, startAt: 2), nextCursor: 'c3'),
        )
        ..on(
          'GET',
          _path,
          times: 1,
          body: pageWire(spendsWire(1, startAt: 4)),
        );
      final container = _container(api);
      await _loadFirstPage(container);

      await _notifier(container).loadMore();
      expect(_ids(_state(container)),
          ['txn_0000', 'txn_0001', 'txn_0002', 'txn_0003']);
      expect(_state(container).nextCursor, 'c3');

      await _notifier(container).loadMore();
      expect(_state(container).items, hasLength(5));
      expect(_state(container).hasMore, isFalse);
      expect(_state(container).isLoadingMore, isFalse);

      // The last page is in: this one must not reach the network.
      await _notifier(container).loadMore();

      final requests = api.requestsFor('GET', _path);
      expect(requests, hasLength(3));
      expect(requests[1].query['cursor'], 'c2');
      expect(requests[2].query['cursor'], 'c3');
      // The cursor does not change which month or page size is asked for.
      expect(requests.map((r) => r.query['month']).toSet(), {'2026-09'});
      expect(requests.map((r) => r.query['limit']).toSet(),
          {'${FeedNotifier.pageSize}'});
    });

    test('allocates a new list and leaves the old one alone', () async {
      final api = FakeApi()
        ..on('GET', _path,
            times: 1, body: pageWire(spendsWire(2), nextCursor: 'c2'))
        ..on('GET', _path, body: pageWire(spendsWire(2, startAt: 2)));
      final container = _container(api);
      final before = await _loadFirstPage(container);
      final beforeItems = before.items;

      await _notifier(container).loadMore();
      final after = _state(container);

      expect(identical(after.items, beforeItems), isFalse);
      expect(beforeItems, hasLength(2));
      expect(before.nextCursor, 'c2');
      expect(() => after.items.add(txn()), throwsUnsupportedError);
    });

    test('a second call while one is in flight is a no-op', () async {
      final api = FakeApi()
        ..on('GET', _path,
            times: 1, body: pageWire(spendsWire(2), nextCursor: 'c2'))
        ..on(
          'GET',
          _path,
          delay: const Duration(milliseconds: 20),
          body: pageWire(spendsWire(2, startAt: 2)),
        );
      final container = _container(api);
      await _loadFirstPage(container);

      final first = _notifier(container).loadMore();
      expect(_state(container).isLoadingMore, isTrue);
      final second = _notifier(container).loadMore();
      await Future.wait([first, second]);

      expect(api.requestsFor('GET', _path), hasLength(2));
      expect(_state(container).items, hasLength(4));
      expect(_state(container).isLoadingMore, isFalse);
    });

    test('does nothing before page one has arrived', () async {
      final api = FakeApi()
        ..on(
          'GET',
          _path,
          delay: const Duration(milliseconds: 20),
          body: pageWire(spendsWire(2), nextCursor: 'c2'),
        );
      final container = _container(api);
      readAndKeepAlive(container, feedProvider(_key));

      await _notifier(container).loadMore();
      await container.read(feedProvider(_key).future);

      expect(api.requestsFor('GET', _path), hasLength(1));
    });

    test('a failure keeps the rows, parks the error, and can be retried',
        () async {
      final api = FakeApi()
        ..on('GET', _path,
            times: 1, body: pageWire(spendsWire(2), nextCursor: 'c2'))
        ..on('GET', _path, body: pageWire(spendsWire(2, startAt: 2)));
      final container = _container(api);
      await _loadFirstPage(container);
      api.failOnce('GET', _path);

      await _notifier(container).loadMore();

      final failed = container.read(feedProvider(_key));
      expect(failed, isA<AsyncData<FeedState>>(),
          reason: 'a failed page 2 must not throw away page 1');
      expect(failed.requireValue.items, hasLength(2));
      expect(failed.requireValue.loadMoreError, isA<ServerError>());
      expect(failed.requireValue.isLoadingMore, isFalse);
      expect(failed.requireValue.nextCursor, 'c2');

      await _notifier(container).loadMore();

      expect(_state(container).items, hasLength(4));
      expect(_state(container).loadMoreError, isNull);
      expect(api.requestsFor('GET', _path).last.query['cursor'], 'c2');
    });
  });

  group('FeedNotifier.refresh', () {
    test('starts again from page one and resets the cursor', () async {
      final api = FakeApi()
        ..on('GET', _path,
            times: 1, body: pageWire(spendsWire(2), nextCursor: 'c2'))
        ..on(
          'GET',
          _path,
          times: 1,
          body: pageWire(spendsWire(2, startAt: 2), nextCursor: 'c3'),
        )
        ..on(
          'GET',
          _path,
          times: 1,
          body: pageWire([txnWire(id: 'txn_new')], nextCursor: 'fresh'),
        );
      final container = _container(api);
      await _loadFirstPage(container);
      await _notifier(container).loadMore();
      expect(_state(container).nextCursor, 'c3');

      await _notifier(container).refresh();

      expect(_ids(_state(container)), ['txn_new']);
      expect(_state(container).nextCursor, 'fresh');
      final requests = api.requestsFor('GET', _path);
      expect(requests, hasLength(3));
      expect(requests.last.query.containsKey('cursor'), isFalse);
    });

    test('drops a page that was requested before the refresh', () async {
      final api = FakeApi()
        ..on('GET', _path,
            times: 1, body: pageWire(spendsWire(2), nextCursor: 'c2'))
        // Page 2 is slow, and lands after the refresh has finished.
        ..on(
          'GET',
          _path,
          times: 1,
          delay: const Duration(milliseconds: 50),
          body: pageWire(spendsWire(2, startAt: 2)),
        )
        ..on('GET', _path, times: 1, body: pageWire([txnWire(id: 'txn_new')]));
      final container = _container(api);
      await _loadFirstPage(container);

      final stale = _notifier(container).loadMore();
      await _notifier(container).refresh();
      await stale;

      expect(_ids(_state(container)), ['txn_new'],
          reason: 'old page 2 must not be glued onto the new page 1');
      expect(_state(container).isLoadingMore, isFalse);
    });

    test('a failed refresh surfaces as AsyncError and never throws', () async {
      final api = FakeApi()
        ..on('GET', _path, times: 1, body: pageWire(spendsWire(2)))
        ..respondError('GET', _path, status: 500, code: 'INTERNAL');
      final container = _container(api);
      await _loadFirstPage(container);

      await _notifier(container).refresh();

      final value = container.read(feedProvider(_key));
      expect(value.hasError, isTrue);
      expect(value.error, isA<ServerError>());
    });
  });
}
