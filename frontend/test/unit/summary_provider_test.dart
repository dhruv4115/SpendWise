import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/errors/bank_error.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/auth/state/session_provider.dart';
import 'package:spendwise/features/overview/data/aggregator.dart';
import 'package:spendwise/features/overview/domain/month_summary.dart';
import 'package:spendwise/features/overview/state/overview_provider.dart';
import 'package:spendwise/features/overview/state/summary_provider.dart';
import 'package:spendwise/features/transactions/domain/transaction.dart';
import 'package:spendwise/features/transactions/state/feed_provider.dart';

import '../helpers/categories.dart';
import '../helpers/container.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/summaries.dart';
import '../helpers/transactions.dart';

const String _month = '2026-09';
const FeedKey _feed = FeedKey(month: _month);

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

Future<MonthSummary> _loadSummary(ProviderContainer container) {
  readAndKeepAlive(container, summaryProvider(_month));
  return container.read(summaryProvider(_month).future);
}

final List<Transaction> _rows = [
  txn(id: 'txn_1', amountPaise: -45000, at: DateTime(2026, 9, 20, 12)),
  txn(
    id: 'txn_2',
    merchantName: 'Uber',
    category: 'transport',
    amountPaise: -12000,
    at: DateTime(2026, 9, 12, 9),
  ),
  txn(
    id: 'txn_3',
    merchantName: 'Amazon',
    category: 'shopping',
    amountPaise: 3000,
    at: DateTime(2026, 9, 4, 18),
  ),
];

Map<String, Object?> _page(List<Transaction> rows, {String? nextCursor}) =>
    pageWire([for (final row in rows) row.toJson()], nextCursor: nextCursor);

void main() {
  group('summaryProvider', () {
    test('loads the server summary for the month', () async {
      final api = FakeApi()..on('GET', '/summary', body: septemberWire());
      final container = _container(api);

      final summary = await _loadSummary(container);

      expect(summary.month, _month);
      expect(summary.totalPaise, 1090000);
      expect(summary.prevTotalPaise, 1000000);
      expect(summary.byCategory['food'], 450000);
      expect(summary.deltaPercent, 9);
      final request = api.requestsFor('GET', '/summary').single;
      expect(request.query, {'month': _month});
      expect(request.authorization, 'Bearer ${testSession.token}');
    });

    test('a failure is an AsyncError carrying the BankError', () async {
      final api = FakeApi()
        ..respondError(
          'GET',
          '/summary',
          status: 503,
          code: 'UPSTREAM_UNAVAILABLE',
          message: 'The bank is unavailable.',
        );
      final container = _container(api);

      await expectLater(_loadSummary(container), throwsA(isA<ServerError>()));

      final value = container.read(summaryProvider(_month));
      expect(value, isA<AsyncError<MonthSummary>>());
      expect(
          (value.error! as BankError).userMessage, 'The bank is unavailable.');
    });

    test('a malformed summary is a BankError too, not a FormatException',
        () async {
      final api = FakeApi()
        ..on('GET', '/summary', body: {
          ...summaryWire(),
          'totalPaise': 12.5,
        });
      final container = _container(api);

      await expectLater(
        _loadSummary(container),
        throwsA(
          isA<UnknownError>()
              .having((e) => e.code, 'code', 'MALFORMED_SUMMARY'),
        ),
      );
    });

    test('an empty month yields zeros', () async {
      final api = FakeApi()
        ..on('GET', '/summary', body: summaryWire(month: '2026-05'));
      final container = _container(api);
      readAndKeepAlive(container, summaryProvider('2026-05'));

      final summary = await container.read(summaryProvider('2026-05').future);

      expect(summary.totalPaise, 0);
      expect(summary.prevTotalPaise, 0);
      expect(summary.byCategory, isEmpty);
      expect(summary.byDay, isEmpty);
      expect(summary.isEmpty, isTrue);
      expect(summary.deltaPaise, 0);
      expect(summary.deltaPercent, isNull, reason: 'nothing to divide by');
    });

    test('refresh fetches again and keeps the numbers while it does', () async {
      final api = FakeApi()
        ..on('GET', '/summary', times: 1, body: septemberWire())
        ..on(
          'GET',
          '/summary',
          delay: const Duration(milliseconds: 20),
          body: summaryWire(byCategory: const {'food': 1000}),
        );
      final container = _container(api);
      await _loadSummary(container);

      final pending =
          container.read(summaryProvider(_month).notifier).refresh();
      final during = container.read(summaryProvider(_month));
      expect(during.isLoading, isTrue);
      expect(during.valueOrNull?.totalPaise, 1090000);
      await pending;

      expect(container.read(summaryProvider(_month)).requireValue.totalPaise,
          1000);
      expect(api.requestsFor('GET', '/summary'), hasLength(2));
    });
  });

  group('localSummaryProvider', () {
    test('stays null while the feed has pages to come', () async {
      final api = FakeApi()
        ..on('GET', '/summary', body: septemberWire())
        ..on('GET', '/transactions', body: _page(_rows, nextCursor: 'c2'));
      final container = _container(api);
      readAndKeepAlive(container, localSummaryProvider(_month));
      await _loadSummary(container);
      await container.read(feedProvider(_feed).future);

      expect(await container.read(localSummaryProvider(_month).future), isNull);
    });

    test(
        'is the aggregator over the feed once it is complete, with last '
        "month's total from the server", () async {
      final api = FakeApi()
        ..on('GET', '/summary', body: septemberWire())
        ..on('GET', '/transactions', body: _page(_rows));
      final container = _container(api);
      readAndKeepAlive(container, localSummaryProvider(_month));
      await _loadSummary(container);
      await container.read(feedProvider(_feed).future);

      final local = await container.read(localSummaryProvider(_month).future);

      final expected =
          Aggregator.summarise(_rows, _month, prevTotalPaise: 1000000);
      expect(local, expected);
      expect(local!.totalPaise, 45000 + 12000 - 3000);
    });

    test('follows an optimistic recategorise with no request', () async {
      final api = FakeApi()
        ..on('GET', '/summary', body: septemberWire())
        ..on('GET', '/transactions', body: _page(_rows));
      final container = _container(api);
      readAndKeepAlive(container, localSummaryProvider(_month));
      await _loadSummary(container);
      await container.read(feedProvider(_feed).future);
      await container.read(localSummaryProvider(_month).future);

      container
          .read(feedProvider(_feed).notifier)
          .applyCategory('travel', where: (row) => row.id == 'txn_2');
      final moved = await container.read(localSummaryProvider(_month).future);

      expect(moved!.byCategory['travel'], 12000);
      expect(moved.byCategory.containsKey('transport'), isFalse);
      expect(moved.totalPaise, 54000, reason: 'moving money changes no total');
      expect(api.requestsFor('GET', '/summary'), hasLength(1));
      expect(api.requestsFor('GET', '/transactions'), hasLength(1));
    });
  });

  group('overviewProvider', () {
    Future<ProviderContainer> loaded(FakeApi api) async {
      final container = _container(api);
      // The categories belong to the signed-in customer.
      container.read(sessionProvider);
      await pumpEventQueue();
      readAndKeepAlive(container, overviewProvider(_month));
      await container.read(summaryProvider(_month).future);
      await container.read(feedProvider(_feed).future);
      await pumpEventQueue();
      return container;
    }

    test('is memoised: the same data until the numbers change', () async {
      final api = FakeApi()
        ..on('GET', '/summary', body: septemberWire())
        ..on('GET', '/categories', body: categoriesWire())
        ..on('GET', '/transactions', body: _page(_rows, nextCursor: 'c2'));
      final container = await loaded(api);

      final first = container.read(overviewProvider(_month)).requireValue;
      final second = container.read(overviewProvider(_month)).requireValue;

      expect(identical(first, second), isTrue);
      expect(identical(first.slices, second.slices), isTrue);
      expect(first.summary.totalPaise, 1090000, reason: 'server numbers');
      expect(first.slices.first.label, 'Food & Dining');
    });

    test('prefers the device summary once the feed is complete', () async {
      final api = FakeApi()
        ..on('GET', '/summary', body: septemberWire())
        ..on('GET', '/categories', body: categoriesWire())
        ..on('GET', '/transactions', body: _page(_rows));
      final container = await loaded(api);

      final data = container.read(overviewProvider(_month)).requireValue;

      expect(data.summary.totalPaise, 54000);
      expect(data.summary.prevTotalPaise, 1000000);
      expect(data.refundedCategories, ['Shopping']);
    });

    test('still draws, with readable ids, when categories fail', () async {
      final api = FakeApi()
        ..on('GET', '/summary', body: septemberWire())
        ..respondError('GET', '/categories', status: 503, code: 'DOWN')
        ..on('GET', '/transactions', body: _page(_rows, nextCursor: 'c2'));
      final container = await loaded(api);

      final data = container.read(overviewProvider(_month)).requireValue;

      expect(data.slices.first.label, 'Food');
      expect(data.slices.first.argb, isNull);
    });
  });
}
