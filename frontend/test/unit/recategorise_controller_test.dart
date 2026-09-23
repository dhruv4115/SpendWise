import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/errors/bank_error.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/budgets/state/budgets_provider.dart';
import 'package:spendwise/features/merchants/state/merchants_provider.dart';
import 'package:spendwise/features/overview/data/aggregator.dart';
import 'package:spendwise/features/overview/data/ledger_check.dart';
import 'package:spendwise/features/overview/state/summary_provider.dart';
import 'package:spendwise/features/transactions/domain/transaction.dart';
import 'package:spendwise/features/transactions/state/feed_provider.dart';
import 'package:spendwise/features/transactions/state/recategorise_controller.dart';

import '../helpers/container.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/transactions.dart';

const String _september = '2026-09';
const String _august = '2026-08';
const FeedKey _feed = FeedKey(month: _september);
const FeedKey _augustFeed = FeedKey(month: _august);

const String _feedPath = '/transactions';
const String _undoPath = '/transactions/undo';
const String _undoToken = 'undo-token-1';

String _itemPath(String id) => '/transactions/$id';

/// September as the server holds it: Swiggy three times under three
/// spellings and two categories (one of them a refund), an Uber ride and a
/// BigBasket order that is already in Groceries.
final List<Transaction> _rows = [
  txn(
    id: 'txn_s1',
    merchantRaw: 'SWIGGY*1234',
    amountPaise: -45250,
    at: DateTime(2026, 9, 22, 20),
  ),
  txn(
    id: 'txn_u1',
    merchantName: 'Uber',
    category: 'transport',
    amountPaise: -18900,
    at: DateTime(2026, 9, 22, 9),
  ),
  txn(
    id: 'txn_s2',
    merchantRaw: 'SWIGGY *8891',
    amountPaise: -31000,
    at: DateTime(2026, 9, 18, 13),
  ),
  txn(
    id: 'txn_b1',
    merchantName: 'BigBasket',
    category: 'groceries',
    amountPaise: -120000,
    at: DateTime(2026, 9, 15, 18),
  ),
  txn(
    id: 'txn_s3',
    merchantRaw: 'swiggy-2201',
    category: 'shopping',
    amountPaise: 9900,
    at: DateTime(2026, 9, 10, 12),
  ),
];

final List<Transaction> _augustRows = [
  txn(id: 'txn_a1', amountPaise: -27500, at: DateTime(2026, 8, 30, 21)),
  txn(
    id: 'txn_a2',
    merchantName: 'Ola',
    category: 'transport',
    amountPaise: -9000,
    at: DateTime(2026, 8, 12, 8),
  ),
];

Transaction _original(String id) =>
    [..._rows, ..._augustRows].firstWhere((txn) => txn.id == id);

Map<String, Object?> _page(List<Transaction> rows, {String? nextCursor}) =>
    pageWire([for (final row in rows) row.toJson()], nextCursor: nextCursor);

/// What the server answers a PATCH with.
Map<String, Object?> _patched(
  String id,
  String category,
  List<String> changedIds,
) {
  return {
    'updated': _original(id).copyWith(category: category).toJson(),
    'changedIds': changedIds,
    'undoToken': _undoToken,
  };
}

/// [rows] with [ids] moved to [category] — the server's side of a change.
List<Transaction> _moved(
  List<Transaction> rows,
  Set<String> ids,
  String category,
) {
  return [
    for (final row in rows)
      ids.contains(row.id) ? row.copyWith(category: category) : row,
  ];
}

Map<String, Object?> _summary(List<Transaction> rows, String month) =>
    Aggregator.summarise(rows, month).toJson();

Map<String, Object?> _budgets(List<Transaction> rows, String month) => {
      'items': [
        {
          'category': 'food',
          'month': month,
          'limitPaise': 500000,
          'spentPaise': Aggregator.byCategory(rows)['food'] ?? 0,
        },
      ],
    };

Map<String, Object?> _merchants(List<Transaction> rows) => {
      'items': [
        for (final insight in Aggregator.merchantInsights(rows))
          insight.toJson(),
      ],
    };

/// The production providers, repositories and Dio client on a fake
/// transport.
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

Future<FeedState> _loadFeed(ProviderContainer container,
    [FeedKey key = _feed]) {
  readAndKeepAlive(container, feedProvider(key));
  return container.read(feedProvider(key).future);
}

FeedState _feedState(ProviderContainer container, [FeedKey key = _feed]) =>
    container.read(feedProvider(key)).requireValue;

/// Every loaded row's category, by id.
Map<String, String> _categories(
  ProviderContainer container, [
  FeedKey key = _feed,
]) {
  return {
    for (final row in _feedState(container, key).items) row.id: row.category,
  };
}

RecategoriseController _controller(ProviderContainer container, String id) {
  readAndKeepAlive(container, recategoriseControllerProvider(id));
  return container.read(recategoriseControllerProvider(id).notifier);
}

AsyncValue<RecategoriseState> _controllerState(
  ProviderContainer container,
  String id,
) =>
    container.read(recategoriseControllerProvider(id));

T _succeeded<T>(RecategoriseOutcome<T> outcome) => switch (outcome) {
      RecategoriseSucceeded(:final value) => value,
      RecategoriseFailed(:final error) =>
        fail('Expected success, got ${error.runtimeType}'),
    };

BankError _failed<T>(RecategoriseOutcome<T> outcome) => switch (outcome) {
      RecategoriseFailed(:final error) => error,
      RecategoriseSucceeded() => fail('Expected a failure, got success'),
    };

void main() {
  group('commit', () {
    test('moves the row on the same frame, then puts it back exactly on a 422',
        () async {
      final api = FakeApi()
        ..on('GET', _feedPath, body: _page(_rows))
        ..respondError(
          'PATCH',
          _itemPath('txn_s1'),
          status: 422,
          code: 'VALIDATION_FAILED',
          message: 'That category does not exist.',
          details: {'category': 'Unknown category.'},
          delay: const Duration(milliseconds: 20),
        );
      final container = _container(api);
      final original = await _loadFeed(container);
      final controller = _controller(container, 'txn_s1')..beginEdit();

      final pending = controller.commit(
        transaction: original.find('txn_s1')!,
        category: 'crypto',
        applyToMerchant: false,
      );

      // Nothing has been awaited: this is the frame the customer tapped on.
      expect(_categories(container)['txn_s1'], 'crypto');
      expect(_categories(container)['txn_s2'], 'food',
          reason: 'only this transaction, not its merchant');
      expect(_controllerState(container, 'txn_s1').isLoading, isTrue);

      final error = _failed(await pending);

      expect(error, isA<ValidationError>());
      expect(error.userMessage, 'That category does not exist.');
      expect(_feedState(container), original,
          reason: 'the rollback restores the feed exactly');

      final state = _controllerState(container, 'txn_s1');
      expect(state.hasError, isTrue);
      expect(state.error, isA<ValidationError>());
      expect(state.requireValue.applied, isNull);

      final patch = api.requestsFor('PATCH', _itemPath('txn_s1')).single;
      expect(patch.jsonBody, {'category': 'crypto', 'applyToMerchant': false});
      expect(patch.idempotencyKey, isNotNull);
      expect(patch.idempotencyKey, state.requireValue.idempotencyKey,
          reason: 'a 422 is no reason to change keys');
    });

    test('applyToMerchant moves every loaded row with that merchant key',
        () async {
      final api = FakeApi()
        ..on('GET', _feedPath, times: 1, body: _page(_rows))
        ..on('GET', _feedPath, times: 1, body: _page(_augustRows))
        ..on(
          'PATCH',
          _itemPath('txn_s1'),
          delay: const Duration(milliseconds: 20),
          body: _patched('txn_s1', 'groceries', [
            'txn_s1',
            'txn_s2',
            'txn_s3',
            'txn_a1',
            // A Swiggy order from a month nobody has opened.
            'txn_s_june',
          ]),
        );
      final container = _container(api);
      final september = await _loadFeed(container);
      await _loadFeed(container, _augustFeed);
      final controller = _controller(container, 'txn_s1');

      final pending = controller.commit(
        transaction: september.find('txn_s1')!,
        category: 'groceries',
        applyToMerchant: true,
      );

      // Every spelling, the refund included, in both loaded months.
      expect(_categories(container), {
        'txn_s1': 'groceries',
        'txn_u1': 'transport',
        'txn_s2': 'groceries',
        'txn_b1': 'groceries',
        'txn_s3': 'groceries',
      });
      expect(_categories(container, _augustFeed), {
        'txn_a1': 'groceries',
        'txn_a2': 'transport',
      });

      final change = _succeeded(await pending);

      expect(change.applyToMerchant, isTrue);
      expect(change.changedIds, hasLength(5));
      expect(change.previousCategories, {
        'txn_s1': 'food',
        'txn_s2': 'food',
        'txn_s3': 'shopping',
        'txn_a1': 'food',
      });
      expect(_categories(container)['txn_s3'], 'groceries',
          reason: 'success keeps the optimistic rows');
      expect(api.requestsFor('GET', _feedPath), hasLength(2),
          reason: 'the feed is patched, never reloaded');
      expect(
        api.requestsFor('PATCH', _itemPath('txn_s1')).single.jsonBody,
        {'category': 'groceries', 'applyToMerchant': true},
      );
    });

    test(
        'a retry after a timeout reuses the same Idempotency-Key and applies '
        'once', () async {
      final api = FakeApi()
        ..on('GET', _feedPath, body: _page(_rows))
        ..on('GET', '/summary', times: 1, body: _summary(_rows, _september))
        ..on(
          'GET',
          '/summary',
          times: 1,
          body: _summary(_moved(_rows, {'txn_s1'}, 'groceries'), _september),
        )
        ..on(
          'PATCH',
          _itemPath('txn_s1'),
          body: _patched('txn_s1', 'groceries', ['txn_s1']),
        )
        // Registered last, answers first: the server acts on the first
        // attempt, and its answer never arrives.
        ..timeoutOnce('PATCH', _itemPath('txn_s1'));
      final container = _container(api);
      final feed = await _loadFeed(container);
      readAndKeepAlive(container, summaryProvider(_september));
      await container.read(summaryProvider(_september).future);
      final controller = _controller(container, 'txn_s1')..beginEdit();
      final key =
          _controllerState(container, 'txn_s1').requireValue.idempotencyKey;
      expect(key, isNotNull,
          reason: 'the key exists from the moment the '
              'sheet opens');

      final first = _failed(
        await controller.commit(
          transaction: feed.find('txn_s1')!,
          category: 'groceries',
          applyToMerchant: false,
        ),
      );
      expect(first, isA<NetworkError>());
      expect(first.isRetryable, isTrue);
      expect(_categories(container)['txn_s1'], 'food');

      final change = _succeeded(
        await controller.commit(
          transaction: _feedState(container).find('txn_s1')!,
          category: 'groceries',
          applyToMerchant: false,
        ),
      );

      final patches = api.requestsFor('PATCH', _itemPath('txn_s1'));
      expect(patches, hasLength(2));
      expect(patches.map((request) => request.idempotencyKey).toSet(), {key});
      expect(patches.first.jsonBody, patches.last.jsonBody);

      // Applied once: the row moved, what undo would restore is the real
      // original rather than the first attempt's optimistic value, and the
      // summary was refetched once, not once per attempt.
      expect(_categories(container)['txn_s1'], 'groceries');
      expect(change.previousCategories, {'txn_s1': 'food'});
      await container.read(summaryProvider(_september).future);
      expect(api.requestsFor('GET', '/summary'), hasLength(2));

      // It landed, so the next edit is a new action with a new key.
      controller.beginEdit();
      expect(
        _controllerState(container, 'txn_s1').requireValue.idempotencyKey,
        allOf(isNotNull, isNot(key)),
      );
    });

    test('a second commit while one is in flight sends nothing', () async {
      final api = FakeApi()
        ..on('GET', _feedPath, body: _page(_rows))
        ..on(
          'PATCH',
          _itemPath('txn_s1'),
          delay: const Duration(milliseconds: 20),
          body: _patched('txn_s1', 'groceries', ['txn_s1']),
        );
      final container = _container(api);
      final feed = await _loadFeed(container);
      final controller = _controller(container, 'txn_s1');

      final first = controller.commit(
        transaction: feed.find('txn_s1')!,
        category: 'groceries',
        applyToMerchant: false,
      );
      final second = _failed(
        await controller.commit(
          transaction: feed.find('txn_s1')!,
          category: 'travel',
          applyToMerchant: false,
        ),
      );
      _succeeded(await first);

      expect(second, isA<ConflictError>());
      expect(api.requestsFor('PATCH', _itemPath('txn_s1')), hasLength(1));
      expect(_categories(container)['txn_s1'], 'groceries');
    });
  });

  group('undo', () {
    /// A Swiggy-wide move to Groceries that the server has accepted.
    Future<(ProviderContainer, RecategoriseController, FeedState)> committed(
      FakeApi api,
    ) async {
      api
        ..on('GET', _feedPath, times: 1, body: _page(_rows))
        ..on(
          'PATCH',
          _itemPath('txn_s1'),
          body: _patched(
            'txn_s1',
            'groceries',
            ['txn_s1', 'txn_s2', 'txn_s3', 'txn_s_june'],
          ),
        );
      final container = _container(api);
      final original = await _loadFeed(container);
      final controller = _controller(container, 'txn_s1');
      _succeeded(
        await controller.commit(
          transaction: original.find('txn_s1')!,
          category: 'groceries',
          applyToMerchant: true,
        ),
      );
      return (container, controller, original);
    }

    test('restores every changed id, on screen before the server answers',
        () async {
      final api = FakeApi()
        ..on(
          'POST',
          _undoPath,
          delay: const Duration(milliseconds: 20),
          body: {
            'restoredIds': ['txn_s1', 'txn_s2', 'txn_s3', 'txn_s_june'],
          },
        );
      final (container, controller, original) = await committed(api);
      expect(_categories(container)['txn_s3'], 'groceries');

      final pending = controller.undo();

      // Each row back to its own category — two food, one shopping — before
      // the request has even left.
      expect(_feedState(container), original);

      final restored = _succeeded(await pending);

      expect(restored, ['txn_s1', 'txn_s2', 'txn_s3', 'txn_s_june']);
      expect(_feedState(container), original);
      expect(
          _controllerState(container, 'txn_s1').requireValue.applied, isNull);

      final post = api.requestsFor('POST', _undoPath).single;
      final patch = api.requestsFor('PATCH', _itemPath('txn_s1')).single;
      expect(post.jsonBody, {'undoToken': _undoToken});
      expect(post.idempotencyKey, isNotNull);
      expect(post.idempotencyKey, isNot(patch.idempotencyKey),
          reason: 'undo is its own action with its own key');
    });

    test('re-reads a restored row that only loaded after the change', () async {
      final api = FakeApi()
        ..on('GET', _feedPath,
            times: 1, body: _page(_rows.take(2).toList(), nextCursor: 'c2'))
        // Page two arrives after the change landed, so the server already
        // has Swiggy in Groceries.
        ..on(
          'GET',
          _feedPath,
          times: 1,
          body: _page(
            _moved(_rows.skip(2).toList(), {'txn_s2', 'txn_s3'}, 'groceries'),
          ),
        )
        ..on(
          'PATCH',
          _itemPath('txn_s1'),
          body: _patched('txn_s1', 'groceries', ['txn_s1', 'txn_s2', 'txn_s3']),
        )
        ..on('POST', _undoPath, body: {
          'restoredIds': ['txn_s1', 'txn_s2', 'txn_s3'],
        })
        ..on('GET', _itemPath('txn_s2'), body: _original('txn_s2').toJson())
        ..on('GET', _itemPath('txn_s3'), body: _original('txn_s3').toJson());
      final container = _container(api);
      final firstPage = await _loadFeed(container);
      final controller = _controller(container, 'txn_s1');
      _succeeded(
        await controller.commit(
          transaction: firstPage.find('txn_s1')!,
          category: 'groceries',
          applyToMerchant: true,
        ),
      );
      await container.read(feedProvider(_feed).notifier).loadMore();
      expect(_categories(container)['txn_s3'], 'groceries');

      _succeeded(await controller.undo());

      expect(_categories(container), {
        for (final row in _rows) row.id: row.category,
      });
      expect(api.requestsFor('GET', _itemPath('txn_s2')), hasLength(1));
      expect(api.requestsFor('GET', _itemPath('txn_s1')), isEmpty,
          reason: 'a row whose old category is known is not re-read');
    });

    test('a failed undo shows the change again, and the retry reuses its key',
        () async {
      final api = FakeApi()
        ..on('POST', _undoPath, body: {
          'restoredIds': ['txn_s1', 'txn_s2', 'txn_s3', 'txn_s_june'],
        });
      final (container, controller, original) = await committed(api);
      api.failOnce('POST', _undoPath);

      final error = _failed(await controller.undo());

      expect(error, isA<ServerError>());
      expect(_categories(container)['txn_s2'], 'groceries',
          reason: 'the server still has the change');
      expect(_controllerState(container, 'txn_s1').requireValue.applied,
          isNotNull);

      _succeeded(await controller.undo());

      expect(_feedState(container), original);
      final posts = api.requestsFor('POST', _undoPath);
      expect(posts, hasLength(2));
      expect(posts.first.idempotencyKey, posts.last.idempotencyKey);
    });
  });

  group('downstream', () {
    final afterChange = _moved(_rows, {'txn_s1'}, 'travel');

    test(
        'summary, budgets and merchants refetch once for the month; the '
        'feed never does', () async {
      final api = FakeApi()
        ..on('GET', _feedPath, body: _page(_rows))
        // In the order they are asked for: September, August, then
        // September again after the change and after the undo.
        ..on('GET', '/summary', times: 1, body: _summary(_rows, _september))
        ..on('GET', '/summary', times: 1, body: _summary(_augustRows, _august))
        ..on('GET', '/summary',
            times: 1, body: _summary(afterChange, _september))
        ..on('GET', '/summary', times: 1, body: _summary(_rows, _september))
        ..on('GET', '/budgets', times: 1, body: _budgets(_rows, _september))
        ..on('GET', '/budgets',
            times: 1, body: _budgets(afterChange, _september))
        ..on('GET', '/budgets', times: 1, body: _budgets(_rows, _september))
        ..on('GET', '/merchants', times: 1, body: _merchants(_rows))
        ..on('GET', '/merchants', times: 1, body: _merchants(afterChange))
        ..on('GET', '/merchants', times: 1, body: _merchants(_rows))
        ..on(
          'PATCH',
          _itemPath('txn_s1'),
          body: _patched('txn_s1', 'travel', ['txn_s1']),
        )
        ..on('POST', _undoPath, body: {
          'restoredIds': ['txn_s1'],
        });
      final container = _container(api);
      final feed = await _loadFeed(container);

      Future<void> loadDownstream() async {
        await container.read(summaryProvider(_september).future);
        await container.read(summaryProvider(_august).future);
        await container.read(budgetsProvider(_september).future);
        await container.read(merchantsProvider(_september).future);
      }

      Map<String, int> requestCounts() => {
            for (final path in [
              _feedPath,
              '/summary',
              '/budgets',
              '/merchants'
            ])
              path: api.requestsFor('GET', path).length,
          };

      for (final provider in [
        summaryProvider(_september),
        summaryProvider(_august),
      ]) {
        readAndKeepAlive(container, provider);
      }
      readAndKeepAlive(container, budgetsProvider(_september));
      readAndKeepAlive(container, merchantsProvider(_september));
      await loadDownstream();
      expect(requestCounts(), {
        _feedPath: 1,
        '/summary': 2,
        '/budgets': 1,
        '/merchants': 1,
      });
      debugAssertLedgerBalanced(
        container.read(summaryProvider(_september)).requireValue,
        _feedState(container).items,
      );

      final controller = _controller(container, 'txn_s1');
      _succeeded(
        await controller.commit(
          transaction: feed.find('txn_s1')!,
          category: 'travel',
          applyToMerchant: false,
        ),
      );
      await loadDownstream();
      // Several turns of the event loop: a second, late invalidation would
      // show up here as a fourth request.
      await pumpEventQueue();

      expect(requestCounts(), {
        _feedPath: 1,
        '/summary': 3,
        '/budgets': 2,
        '/merchants': 2,
      });
      expect(
        api.requestsFor('GET', '/summary').map((r) => r.query['month']),
        [_september, _august, _september],
        reason: 'August did not move, so it is not refetched',
      );
      final summary = container.read(summaryProvider(_september)).requireValue;
      expect(summary.byCategory['travel'], 45250);
      debugAssertLedgerBalanced(summary, _feedState(container).items);

      _succeeded(await controller.undo());
      await loadDownstream();
      await pumpEventQueue();

      expect(requestCounts(), {
        _feedPath: 1,
        '/summary': 4,
        '/budgets': 3,
        '/merchants': 3,
      });
      debugAssertLedgerBalanced(
        container.read(summaryProvider(_september)).requireValue,
        _feedState(container).items,
      );
    });

    test('applyToMerchant refetches every loaded month', () async {
      final api = FakeApi()
        ..on('GET', _feedPath, body: _page(_rows))
        ..on('GET', '/summary', times: 1, body: _summary(_rows, _september))
        ..on('GET', '/summary', times: 1, body: _summary(_augustRows, _august))
        ..on('GET', '/summary', body: _summary(_rows, _september))
        ..on(
          'PATCH',
          _itemPath('txn_s1'),
          body: _patched('txn_s1', 'groceries', ['txn_s1', 'txn_a1']),
        );
      final container = _container(api);
      final feed = await _loadFeed(container);
      readAndKeepAlive(container, summaryProvider(_september));
      readAndKeepAlive(container, summaryProvider(_august));
      await container.read(summaryProvider(_september).future);
      await container.read(summaryProvider(_august).future);

      _succeeded(
        await _controller(container, 'txn_s1').commit(
          transaction: feed.find('txn_s1')!,
          category: 'groceries',
          applyToMerchant: true,
        ),
      );
      await container.read(summaryProvider(_september).future);
      await container.read(summaryProvider(_august).future);
      await pumpEventQueue();

      final months =
          api.requestsFor('GET', '/summary').map((r) => r.query['month']);
      expect(months.where((month) => month == _september), hasLength(2));
      expect(months.where((month) => month == _august), hasLength(2));
    });

    test('a failed commit invalidates nothing', () async {
      final api = FakeApi()
        ..on('GET', _feedPath, body: _page(_rows))
        ..on('GET', '/summary', body: _summary(_rows, _september))
        ..respondError(
          'PATCH',
          _itemPath('txn_s1'),
          status: 422,
          code: 'VALIDATION_FAILED',
        );
      final container = _container(api);
      final feed = await _loadFeed(container);
      readAndKeepAlive(container, summaryProvider(_september));
      await container.read(summaryProvider(_september).future);

      _failed(
        await _controller(container, 'txn_s1').commit(
          transaction: feed.find('txn_s1')!,
          category: 'crypto',
          applyToMerchant: false,
        ),
      );
      await pumpEventQueue();

      expect(api.requestsFor('GET', '/summary'), hasLength(1));
      debugAssertLedgerBalanced(
        container.read(summaryProvider(_september)).requireValue,
        _feedState(container).items,
      );
    });
  });
}
