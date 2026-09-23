import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/auth/domain/session.dart';
import 'package:spendwise/features/auth/state/session_provider.dart';
import 'package:spendwise/features/transactions/domain/transaction_filter.dart';
import 'package:spendwise/features/transactions/state/feed_provider.dart';
import 'package:spendwise/features/transactions/state/filter_provider.dart';

import '../helpers/container.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/transactions.dart';

/// Start of 5 Sep and the last millisecond of 12 Sep, local time.
final DateTime _from = DateTime(2026, 9, 5);
final DateTime _to = DateTime(2026, 9, 12, 23, 59, 59, 999);

/// A container whose customer has finished signing in, so the filter —
/// which starts afresh for each customer — is not reset under the test by
/// the keystore read landing late.
Future<ProviderContainer> _signedIn([FakeApi? api]) async {
  final container = makeContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(
        FakeSessionStore(session: testSession),
      ),
      if (api != null) httpClientAdapterProvider.overrideWithValue(api),
    ],
  );
  container.read(sessionProvider);
  await Future<void>.delayed(Duration.zero);
  expect(container.read(sessionProvider), isA<SessionSignedIn>());
  return container;
}

FilterNotifier _filters(ProviderContainer container) =>
    container.read(filterStateNotifier.notifier);

TransactionFilter _filter(ProviderContainer container) =>
    container.read(filterStateNotifier);

void main() {
  group('FilterNotifier', () {
    test('starts with nothing applied', () async {
      final container = await _signedIn();

      expect(_filter(container), TransactionFilter.none);
      expect(container.read(activeFilterCountProvider), 0);
    });

    test('filters combine: each setter adds to the others', () async {
      final container = await _signedIn();

      _filters(container)
        ..setCategory('food')
        ..setQuery('  swig ')
        ..setAmountRange(minPaise: 50000, maxPaise: 200000)
        ..setDateRange(from: _from, to: _to);

      expect(
        _filter(container),
        TransactionFilter(
          category: 'food',
          query: 'swig',
          minPaise: 50000,
          maxPaise: 200000,
          from: _from,
          to: _to,
        ),
      );
      // A range is one filter, whichever ends are set.
      expect(container.read(activeFilterCountProvider), 4);
    });

    test('changing one filter leaves the others alone', () async {
      final container = await _signedIn();
      _filters(container)
        ..setCategory('food')
        ..setQuery('swig')
        ..setAmountRange(minPaise: 50000);

      _filters(container).setCategory('travel');
      expect(_filter(container).category, 'travel');
      expect(_filter(container).query, 'swig');
      expect(_filter(container).minPaise, 50000);

      _filters(container).setAmountRange();
      expect(_filter(container).hasAmountRange, isFalse);
      expect(_filter(container).category, 'travel');
      expect(container.read(activeFilterCountProvider), 2);

      _filters(container).setCategory(null);
      expect(_filter(container).category, isNull);
      expect(_filter(container).query, 'swig');
    });

    test('the search is stored trimmed, so equal searches are one feed',
        () async {
      final container = await _signedIn();

      _filters(container).setQuery('swiggy ');
      final first = _filter(container);
      _filters(container).setQuery(' swiggy');

      expect(_filter(container), first);
      expect(FeedKey(month: '2026-09', filter: first),
          FeedKey(month: '2026-09', filter: _filter(container)));
    });

    test('clear resets every filter at once', () async {
      final container = await _signedIn();
      _filters(container)
        ..setCategory('food')
        ..setQuery('swig')
        ..setAmountRange(minPaise: 100, maxPaise: 900)
        ..setDateRange(from: _from, to: _to);

      _filters(container).clear();

      expect(_filter(container), TransactionFilter.none);
      expect(_filter(container).isActive, isFalse);
      expect(container.read(activeFilterCountProvider), 0);
    });

    test('applyAll replaces everything in one change', () async {
      final container = await _signedIn();
      _filters(container).setQuery('swig');
      final changes = <TransactionFilter>[];
      container.listen<TransactionFilter>(
        filterStateNotifier,
        (_, next) => changes.add(next),
      );

      final fromSheet = TransactionFilter(
        category: 'groceries',
        query: 'swig',
        minPaise: 25050,
        from: _from,
        to: _to,
      );
      _filters(container).applyAll(fromSheet);

      expect(changes, [fromSheet], reason: 'one change, so one request');
      expect(_filter(container), fromSheet);
    });

    test('an equal filter tells nobody', () async {
      final container = await _signedIn();
      _filters(container).setCategory('food');
      var notified = 0;
      container.listen<TransactionFilter>(
        filterStateNotifier,
        (_, __) => notified++,
      );

      _filters(container)
        ..applyAll(const TransactionFilter(category: 'food'))
        ..setCategory('food')
        ..setQuery('   ');

      expect(notified, 0);
    });

    test('outlives every screen: nothing has to be listening', () async {
      final container = await _signedIn();
      _filters(container).setCategory('food');

      // An auto-disposed provider would be gone after this.
      await container.pump();
      await Future<void>.delayed(Duration.zero);

      expect(_filter(container).category, 'food');
    });

    test('locking keeps the filter; another customer starts afresh', () async {
      final container = await _signedIn();
      final session = container.read(sessionProvider.notifier);
      _filters(container).setQuery('pharmacy');

      session
        ..lock()
        ..unlock();
      expect(_filter(container).query, 'pharmacy');

      session.signIn(
        const Session(
          token: 'tok_someone_else_0000',
          user: AuthUser(
            id: 'usr_other_0000',
            name: 'Ravi Kumar',
            email: 'ravi@example.com',
          ),
        ),
      );
      expect(_filter(container), TransactionFilter.none);
    });
  });

  group('the query map for the API', () {
    test('holds only the filters that are set, never a null or blank', () {
      const filter = TransactionFilter(category: 'food', maxPaise: 90000);

      final query = filter.toQueryParameters();

      expect(query, {'category': 'food', 'maxPaise': '90000'});
      expect(query.values, everyElement(isNotEmpty));
      expect(query.values, isNot(contains('null')));
    });

    test('a combined filter sends each of its parts', () async {
      final container = await _signedIn();
      _filters(container)
        ..setCategory('food')
        ..setQuery('swig')
        ..setAmountRange(minPaise: 50000, maxPaise: 200000)
        ..setDateRange(from: _from, to: _to);

      expect(_filter(container).toQueryParameters(), {
        'category': 'food',
        'q': 'swig',
        'minPaise': '50000',
        'maxPaise': '200000',
        'from': _from.toUtc().toIso8601String(),
        'to': _to.toUtc().toIso8601String(),
      });
    });

    test('the feed request carries exactly the set filters and no others',
        () async {
      final api = FakeApi()..on('GET', '/transactions', body: pageWire([]));
      final container = await _signedIn(api);
      _filters(container)
        ..setCategory('food')
        ..setAmountRange(minPaise: 50000)
        ..setQuery('   ');
      final key = FeedKey(month: '2026-09', filter: _filter(container));

      readAndKeepAlive(container, feedProvider(key));
      await container.read(feedProvider(key).future);

      final query = api.requestsFor('GET', '/transactions').single.query;
      expect(query.keys.toSet(), {'month', 'category', 'minPaise', 'limit'});
      expect(query['category'], 'food');
      expect(query['minPaise'], '50000');
      expect(
        query.values.map((value) => '$value'),
        everyElement(allOf(isNotEmpty, isNot('null'))),
      );
    });
  });
}
