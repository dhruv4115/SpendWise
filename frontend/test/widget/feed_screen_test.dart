import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/core/widgets/async_error_view.dart';
import 'package:spendwise/core/widgets/empty_view.dart';
import 'package:spendwise/core/widgets/skeleton.dart';
import 'package:spendwise/features/transactions/presentation/feed_screen.dart';
import 'package:spendwise/features/transactions/state/feed_provider.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';
import 'package:spendwise/features/transactions/widgets/day_header.dart';
import 'package:spendwise/features/transactions/widgets/transaction_tile.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/test_app.dart';
import '../helpers/transactions.dart';

const String _path = '/transactions';

/// The month under test. Every request the feed makes for it — and none of
/// the ones the month strip makes to have its neighbours ready.
const Map<String, String> _thisMonth = {'month': '2026-09'};

List<RecordedRequest> _feedRequests(FakeApi api) =>
    api.requestsFor('GET', _path, query: _thisMonth);

/// Midday on 23 Sep 2026, so "Today" and "Yesterday" are fixed.
final DateTime _now = DateTime(2026, 9, 23, 12);

/// The real rows on screen. The list also inflates one off-stage prototype
/// row per day to measure row height; this leaves those out.
final Finder _rows = find.byWidgetPredicate(
  (widget) =>
      widget is TransactionTile &&
      !identical(widget.transaction, TransactionTile.prototypeTransaction),
);

final Finder _feedScrollable = find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byType(Scrollable),
);

/// Two spends today, one yesterday, and a refund on 20 Sep.
Map<String, Object?> _threeDays({String? nextCursor}) => pageWire(
      [
        txnWire(
          id: 'txn_a',
          merchantName: 'Swiggy',
          amountPaise: -45250,
          at: DateTime(2026, 9, 23, 10),
        ),
        txnWire(
          id: 'txn_b',
          merchantName: 'Uber',
          category: 'transport',
          amountPaise: -18900,
          at: DateTime(2026, 9, 23, 8),
          mode: 'CARD',
        ),
        txnWire(
          id: 'txn_c',
          merchantName: 'BigBasket',
          category: 'groceries',
          amountPaise: -120000,
          at: DateTime(2026, 9, 22, 19),
          mode: 'NETBANKING',
        ),
        txnWire(
          id: 'txn_d',
          merchantName: 'Amazon',
          category: 'shopping',
          amountPaise: 20000,
          at: DateTime(2026, 9, 20, 15),
          mode: 'CARD',
        ),
      ],
      nextCursor: nextCursor,
    );

Widget _feedApp(
  FakeApi api, {
  FakeSessionStore? store,
  TextScaler? textScaler,
}) {
  final Widget screen = textScaler == null
      ? const FeedScreen()
      : Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: const FeedScreen(),
          ),
        );

  return testApp(
    screen,
    overrides: [
      sessionStoreProvider.overrideWithValue(
        store ?? FakeSessionStore(session: testSession),
      ),
      httpClientAdapterProvider.overrideWithValue(api),
      clockProvider.overrideWithValue(() => _now),
    ],
  );
}

/// A phone-sized, 1x surface, so layout numbers mean what they say.
void _usePhoneScreen(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('FeedScreen states', () {
    testWidgets('loading shows a skeleton with day headers', (tester) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..respondAfter(
          'GET',
          _path,
          const Duration(seconds: 2),
          body: _threeDays(),
        );

      await tester.pumpWidget(_feedApp(api));
      await tester.pump();

      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.bySemanticsLabel('Loading transactions'), findsOneWidget);
      expect(_rows, findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byType(SkeletonList), findsNothing);
      expect(_rows, findsNWidgets(4));
    });

    testWidgets('data renders rows under a header for each day', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()..on('GET', _path, body: _threeDays());

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsOneWidget);
      expect(find.byType(DayHeader), findsNWidgets(3));
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('20 Sep'), findsOneWidget);
      // Each header totals the rows beneath it, in the rows' own sign.
      expect(find.text('-₹641.50'), findsOneWidget);
      expect(find.text('-₹1,200.00'), findsNWidgets(2));
      expect(find.text('+₹200.00'), findsNWidgets(2));

      expect(_rows, findsNWidgets(4));
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('-₹452.50'), findsOneWidget);
      expect(find.text('Net banking'), findsOneWidget);
      expect(
          find.text("That's everything for September 2026."), findsOneWidget);
    });

    testWidgets('a refund carries an icon and the word, not just a colour', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()..on('GET', _path, body: _threeDays());

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();

      final refundRow = find.ancestor(
        of: find.text('Amazon'),
        matching: find.byType(TransactionTile),
      );
      expect(
        find.descendant(of: refundRow, matching: find.text('Refund')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: refundRow,
          matching: find.byIcon(Icons.undo_rounded),
        ),
        findsOneWidget,
      );
      expect(find.text('Refund'), findsOneWidget, reason: 'spends say nothing');
      expect(find.bySemanticsLabel('Amazon. Refund of ₹200.00. Card.'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel('Swiggy. Spent ₹452.50. UPI.'), findsOneWidget);
    });

    testWidgets('every row is the same height, refunds included', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()..on('GET', _path, body: _threeDays());

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();

      final heights = {
        for (final element in _rows.evaluate())
          tester.getSize(find.byWidget(element.widget)).height,
      };
      expect(heights, hasLength(1));
    });

    testWidgets('error shows the plain message and Retry reloads', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', _path, body: _threeDays())
        ..failOnce('GET', _path,
            query: _thisMonth, message: 'The bank is unavailable.');

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsOneWidget);
      expect(find.text('The bank is unavailable.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Sign in again'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('UPSTREAM_UNAVAILABLE'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.byType(SkeletonList), findsOneWidget,
          reason: 'a Retry visibly starts over');
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsNothing);
      expect(_rows, findsNWidgets(4));
      expect(_feedRequests(api), hasLength(2));
    });

    testWidgets('an ended session also offers Sign in again', (tester) async {
      _usePhoneScreen(tester);
      final store = FakeSessionStore(session: testSession);
      final api = FakeApi()
        ..respondError(
          'GET',
          _path,
          status: 401,
          code: 'AUTH_TOKEN_INVALID',
          message: 'Your session has ended. Please sign in again.',
        );

      await tester.pumpWidget(_feedApp(api, store: store));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Sign in again'), findsOneWidget);

      final clearsBefore = store.clearCount;
      await tester.tap(find.text('Sign in again'));
      await tester.pumpAndSettle();

      expect(store.clearCount, greaterThan(clearsBefore));
      expect(store.stored, isNull);
    });

    testWidgets('an empty month says so and offers a refresh', (tester) async {
      _usePhoneScreen(tester);
      final api = FakeApi()..on('GET', _path, body: pageWire([]));

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('No transactions in September 2026'), findsOneWidget);
      expect(_rows, findsNothing);

      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      expect(_feedRequests(api), hasLength(2));
    });
  });

  group('FeedScreen behaviour', () {
    testWidgets('pull-to-refresh asks for page one again', (tester) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', _path, times: 1, query: _thisMonth, body: _threeDays())
        ..on(
          'GET',
          _path,
          body: pageWire([
            txnWire(
              id: 'txn_new',
              merchantName: 'Zomato',
              at: DateTime(2026, 9, 23, 11),
            ),
          ]),
        );

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();
      expect(find.text('Zomato'), findsNothing);

      await tester.fling(find.text('Swiggy'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      final requests = _feedRequests(api);
      expect(requests, hasLength(2));
      expect(requests.last.query.containsKey('cursor'), isFalse);
      expect(find.text('Zomato'), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
    });

    testWidgets('the day header stays pinned while its rows scroll under it',
        (tester) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on(
          'GET',
          _path,
          body: pageWire(spendsWire(40, perDay: 40)),
        );

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();

      final pinnedTop = tester.getTopLeft(find.text('Today')).dy;
      await tester.drag(_feedScrollable, const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('Merchant 0'), findsNothing,
          reason: 'the first rows have scrolled away');
      expect(tester.getTopLeft(find.text('Today')).dy, pinnedTop);
    });

    testWidgets('scrolling near the end loads the next page', (tester) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on(
          'GET',
          _path,
          times: 1,
          query: _thisMonth,
          body: pageWire(spendsWire(50), nextCursor: 'c2'),
        )
        ..on('GET', _path, body: pageWire(spendsWire(10, startAt: 50)));

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();
      expect(_feedRequests(api), hasLength(1),
          reason: 'a full first page does not fetch ahead on its own');

      await tester.scrollUntilVisible(
        find.text('Merchant 59'),
        500,
        scrollable: _feedScrollable,
      );
      await tester.pumpAndSettle();

      final requests = _feedRequests(api);
      expect(requests, hasLength(2));
      expect(requests.last.query['cursor'], 'c2');
      expect(
          find.text("That's everything for September 2026."), findsOneWidget);
    });

    testWidgets('a failed page keeps the rows and retries from the footer', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on(
          'GET',
          _path,
          times: 1,
          query: _thisMonth,
          body: pageWire(spendsWire(50), nextCursor: 'c2'),
        )
        ..on('GET', _path, body: pageWire(spendsWire(10, startAt: 50)));

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();
      api.failOnce('GET', _path,
          query: _thisMonth, message: 'The bank is unavailable.');

      await tester.scrollUntilVisible(
        find.text('Retry'),
        500,
        scrollable: _feedScrollable,
      );
      await tester.pumpAndSettle();

      expect(find.text('The bank is unavailable.'), findsOneWidget);
      expect(find.text('Merchant 49'), findsOneWidget);
      // Scrolling about near the end must not hammer a failing server.
      await tester.drag(_feedScrollable, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(_feedRequests(api), hasLength(2));

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Merchant 59'),
        500,
        scrollable: _feedScrollable,
      );

      expect(_feedRequests(api), hasLength(3));
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a short first page pulls in the next without a scroll', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()
        ..on('GET', _path,
            times: 1, query: _thisMonth, body: _threeDays(nextCursor: 'c2'))
        ..on('GET', _path, body: pageWire(spendsWire(2, startAt: 90)));

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();

      expect(_feedRequests(api), hasLength(2));
      expect(_rows, findsNWidgets(6));
    });

    testWidgets('the month arrows move the feed and stop at this month', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final api = FakeApi()..on('GET', _path, body: _threeDays());

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();

      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNull);
      expect(find.byTooltip('Next month'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();

      expect(find.text('August 2026'), findsOneWidget);
      expect(
        api.requestsFor('GET', _path, query: const {'month': '2026-08'}),
        isNotEmpty,
      );
    });

    testWidgets('tapping a row opens /transactions/:id', (tester) async {
      _usePhoneScreen(tester);
      final api = FakeApi()..on('GET', _path, body: _threeDays());
      final harness = routedApp(
        api,
        store: FakeSessionStore(session: testSession),
        initialLocation: Routes.transactionsPath,
        overrides: [clockProvider.overrideWithValue(() => _now)],
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uber'));
      await tester.pumpAndSettle();

      expect(harness.location, Routes.transactionDetail('txn_b'));
    });

    testWidgets('scrolls to row 1,000 building only the rows it shows', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      // 1,000 rows across 30 days, served the way the app asks for them: 20
      // pages of 50, each fetched by scrolling near the end of the last.
      const pages = 20;
      final api = FakeApi();
      for (var page = 0; page < pages; page++) {
        api.on(
          'GET',
          _path,
          times: 1,
          query: _thisMonth,
          body: pageWire(
            spendsWire(
              FeedNotifier.pageSize,
              startAt: page * FeedNotifier.pageSize,
              perDay: 34,
            ),
            nextCursor: page < pages - 1 ? 'c${page + 1}' : null,
          ),
        );
      }

      await tester.pumpWidget(_feedApp(api));
      await tester.pumpAndSettle();
      expect(_rows.evaluate().length, lessThan(30));

      await tester.scrollUntilVisible(
        find.text('Merchant 999'),
        2000,
        scrollable: _feedScrollable,
        maxScrolls: 200,
      );
      await tester.pumpAndSettle();

      expect(_feedRequests(api), hasLength(pages));
      expect(_feedRequests(api).last.query['cursor'], 'c19');
      // A thousand rows loaded; a screenful built.
      expect(_rows.evaluate().length, lessThan(30));
      expect(
          find.text("That's everything for September 2026."), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('FeedScreen at textScaler 2.0', () {
    const scale = TextScaler.linear(2);

    /// A row built to hurt: a long name, a huge refund and the longest mode.
    Map<String, Object?> worstCase() => pageWire([
          txnWire(
            id: 'txn_big',
            merchantName: 'Bharat Sanchar Nigam Limited Postpaid Services',
            category: 'bills',
            amountPaise: 123456789,
            at: DateTime(2026, 9, 23, 10),
            mode: 'NETBANKING',
          ),
          ...spendsWire(30, startAt: 1, perDay: 3),
        ]);

    testWidgets('data renders without overflow, and scrolls', (tester) async {
      _usePhoneScreen(tester, size: const Size(360, 720));
      final api = FakeApi()..on('GET', _path, body: worstCase());

      await tester.pumpWidget(_feedApp(api, textScaler: scale));
      await tester.pumpAndSettle();

      expect(
        MediaQuery.textScalerOf(tester.element(_rows.first)).scale(10),
        20,
        reason: 'the test must really be running at 2.0',
      );
      expect(tester.takeException(), isNull);

      // Rows grow with the text instead of clipping it.
      expect(tester.getSize(_rows.first).height, greaterThan(100));

      await tester.drag(_feedScrollable, const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading renders without overflow', (tester) async {
      _usePhoneScreen(tester, size: const Size(360, 720));
      final api = FakeApi()
        ..respondAfter('GET', _path, const Duration(seconds: 1),
            body: worstCase());

      await tester.pumpWidget(_feedApp(api, textScaler: scale));
      await tester.pump();

      expect(find.byType(SkeletonList), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });

    testWidgets('error renders without overflow', (tester) async {
      _usePhoneScreen(tester, size: const Size(360, 720));
      final api = FakeApi()
        ..respondError('GET', _path, status: 401, code: 'AUTH_TOKEN_INVALID');

      await tester.pumpWidget(_feedApp(api, textScaler: scale));
      await tester.pumpAndSettle();

      expect(find.byType(AsyncErrorView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty renders without overflow', (tester) async {
      _usePhoneScreen(tester, size: const Size(360, 720));
      final api = FakeApi()..on('GET', _path, body: pageWire([]));

      await tester.pumpWidget(_feedApp(api, textScaler: scale));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
