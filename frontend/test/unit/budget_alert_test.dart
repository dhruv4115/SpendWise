import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/errors/bank_error.dart';
import 'package:spendwise/core/network/api_client.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/alerts/data/alert_dedupe_store.dart';
import 'package:spendwise/features/alerts/data/notification_service.dart';
import 'package:spendwise/features/alerts/state/budget_alert_listener.dart';
import 'package:spendwise/features/budgets/state/budgets_provider.dart';
import 'package:spendwise/features/categories/state/categories_provider.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';

import '../helpers/budgets.dart';
import '../helpers/categories.dart';
import '../helpers/container.dart';
import '../helpers/fake_alerts.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';

const String _month = '2026-09';
const String _nextMonth = '2026-10';

/// The clock the container starts on, and the variable a test moves to roll
/// the calendar over.
late DateTime _now;

/// A `GET /budgets` reply: food, with a ₹5,000.00 limit and [spentPaise] of
/// it gone.
Map<String, Object?> _food(int spentPaise, {String month = _month}) {
  return budgetsWire([
    budgetWire(
      category: 'food',
      month: month,
      limitPaise: 500000,
      spentPaise: spentPaise,
    ),
  ]);
}

/// Queues the next `GET /budgets` answer for [month].
///
/// One answer per registration: FakeApi replies with the first route that
/// matches, so a route left open would go on answering with figures the test
/// has already moved past.
void _budgets(
  FakeApi api,
  Map<String, Object?> body, {
  String month = _month,
}) {
  api.on('GET', '/budgets', body: body, query: {'month': month}, times: 1);
}

ProviderContainer _container(
  FakeApi api, {
  required FakeNotificationService notifications,
  required FakeAlertDedupeStore store,
  bool withCategories = false,
}) {
  final container = makeContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(
        FakeSessionStore(session: testSession),
      ),
      httpClientAdapterProvider.overrideWithValue(api),
      clockProvider.overrideWithValue(() => _now),
      notificationServiceProvider.overrideWithValue(notifications),
      alertDedupeStoreProvider.overrideWithValue(store),
    ],
  );
  // An alert names a category from whatever the app has already fetched.
  if (withCategories) readAndKeepAlive(container, categoriesProvider);
  readAndKeepAlive(container, budgetAlertsProvider);
  return container;
}

/// Lets the permission answer, the budgets and the alert queue all land.
Future<void> _settle(
  ProviderContainer container, {
  String month = _month,
}) async {
  await container.read(notificationsAllowedProvider.future);
  try {
    await container.read(budgetsProvider(month).future);
  } on BankError {
    // The listener is what is under test here, not the request.
  }
  await Future<void>.delayed(Duration.zero);
  await container.read(budgetAlertsProvider).settled;
}

/// Refetches the budgets — as a pull-to-refresh or a recategorisation would —
/// with [body] as the new answer, and waits for the listener to see it.
Future<void> _reload(
  ProviderContainer container,
  FakeApi api,
  Map<String, Object?> body, {
  String month = _month,
}) async {
  _budgets(api, body, month: month);
  container.invalidate(budgetsProvider(month));
  await _settle(container, month: month);
}

void main() {
  setUp(() => _now = DateTime(2026, 9, 23, 12));

  group('crossing a threshold', () {
    test('80% fires one alert, naming the category and the percentage',
        () async {
      final notifications = FakeNotificationService();
      final store = FakeAlertDedupeStore();
      final api = FakeApi()..on('GET', '/categories', body: categoriesWire());
      // ₹4,000.00 of ₹5,000.00 is exactly 80%.
      _budgets(api, _food(400000));

      final container = _container(
        api,
        notifications: notifications,
        store: store,
        withCategories: true,
      );
      await _settle(container);

      expect(notifications.shown, hasLength(1));
      final alert = notifications.shown.single;
      expect(alert.title, 'You are nearing your Food & Dining budget');
      expect(
        alert.body,
        'Food & Dining is at 80% of its ₹5,000.00 limit for September 2026.',
      );
      // Routing information only: a month and a category, no identifiers.
      expect(alert.payload, '2026-09|food');
      expect(store.keys, {'2026-09|food|80'});
    });

    test('the same crossing, seen again, fires nothing', () async {
      final notifications = FakeNotificationService();
      final store = FakeAlertDedupeStore();
      final api = FakeApi();
      _budgets(api, _food(400000));

      final container =
          _container(api, notifications: notifications, store: store);
      await _settle(container);
      expect(notifications.shown, hasLength(1));

      // A refresh with the budget unchanged, and another with a little more
      // spent — both still inside the same 80% band.
      await _reload(container, api, _food(400000));
      await _reload(container, api, _food(410000));

      expect(notifications.shown, hasLength(1));
    });

    test('100% fires a second alert, different from the first', () async {
      final notifications = FakeNotificationService();
      final store = FakeAlertDedupeStore();
      final api = FakeApi()..on('GET', '/categories', body: categoriesWire());
      _budgets(api, _food(400000));

      final container = _container(
        api,
        notifications: notifications,
        store: store,
        withCategories: true,
      );
      await _settle(container);

      await _reload(container, api, _food(520000));

      expect(notifications.shown, hasLength(2));
      final over = notifications.shown.last;
      expect(over.title, 'You have used up your Food & Dining budget');
      expect(over.body, contains('104%'));
      // A different notification, not a rewrite of the first one.
      expect(over.id, isNot(notifications.shown.first.id));
      expect(store.keys, {'2026-09|food|80', '2026-09|food|100'});
    });

    test('a budget that arrives already over gets one alert, not two',
        () async {
      final notifications = FakeNotificationService();
      final store = FakeAlertDedupeStore();
      final api = FakeApi();
      _budgets(api, _food(600000));

      final container =
          _container(api, notifications: notifications, store: store);
      await _settle(container);

      expect(notifications.shown, hasLength(1));
      expect(notifications.shown.single.title, contains('used up'));
      // Both thresholds are recorded, so the 80% one can never arrive later.
      expect(store.keys, {'2026-09|food|80', '2026-09|food|100'});
    });

    test('dropping back under 80% and crossing again does not re-fire',
        () async {
      final notifications = FakeNotificationService();
      final store = FakeAlertDedupeStore();
      final api = FakeApi();
      _budgets(api, _food(400000));

      final container =
          _container(api, notifications: notifications, store: store);
      await _settle(container);
      expect(notifications.shown, hasLength(1));

      // A refund takes the category back to 60%…
      await _reload(container, api, _food(300000));
      expect(notifications.shown, hasLength(1));

      // …and the next week's spending takes it to 84% again.
      await _reload(container, api, _food(420000));

      expect(notifications.shown, hasLength(1));
    });

    test('a category under 80% is left alone', () async {
      final notifications = FakeNotificationService();
      final store = FakeAlertDedupeStore();
      final api = FakeApi();
      // 79.8%: near, but not there.
      _budgets(api, _food(399000));

      final container =
          _container(api, notifications: notifications, store: store);
      await _settle(container);

      expect(notifications.shown, isEmpty);
      expect(store.keys, isEmpty);
    });

    test('a category whose refunds outweigh its spends is left alone',
        () async {
      final notifications = FakeNotificationService();
      final store = FakeAlertDedupeStore();
      final api = FakeApi();
      _budgets(api, _food(-20000));

      final container =
          _container(api, notifications: notifications, store: store);
      await _settle(container);

      expect(notifications.shown, isEmpty);
    });
  });

  group('a new month', () {
    test('starts again: the same category crosses 80% and is told', () async {
      final notifications = FakeNotificationService();
      final store = FakeAlertDedupeStore();
      final api = FakeApi();
      _budgets(api, _food(400000));
      _budgets(api, _food(450000, month: _nextMonth), month: _nextMonth);

      final container =
          _container(api, notifications: notifications, store: store);
      await _settle(container);
      expect(notifications.shown, hasLength(1));

      // The first of October. The listener follows the calendar, not the
      // month the customer happens to be browsing.
      _now = DateTime(2026, 10, 1, 9);
      container.invalidate(latestMonthProvider);
      await _settle(container, month: _nextMonth);

      expect(notifications.shown, hasLength(2));
      expect(notifications.shown.last.body, contains('October 2026'));
      expect(notifications.shown.last.payload, '2026-10|food');
      expect(store.keys, {'2026-09|food|80', '2026-10|food|80'});
    });

    test('keys already recorded for it are still honoured', () async {
      final notifications = FakeNotificationService();
      // As if this alert had fired before the app was last closed.
      final store = FakeAlertDedupeStore(seed: {'2026-09|food|80'});
      final api = FakeApi();
      _budgets(api, _food(400000));

      final container =
          _container(api, notifications: notifications, store: store);
      await _settle(container);

      expect(notifications.shown, isEmpty);
    });
  });

  group('permission', () {
    test('refused: nothing is posted, and the budgets are left alone',
        () async {
      final notifications = FakeNotificationService(allowed: false);
      final store = FakeAlertDedupeStore();
      final api = FakeApi();
      _budgets(api, _food(600000));

      final container =
          _container(api, notifications: notifications, store: store);
      await container.read(notificationsAllowedProvider.future);
      await Future<void>.delayed(Duration.zero);
      await container.read(budgetAlertsProvider).settled;

      expect(notifications.initialiseCount, 1);
      expect(notifications.shown, isEmpty);
      // Nothing to alert with is nothing to fetch for: a customer who said no
      // does not pay for a background request all session.
      expect(api.requestsFor('GET', '/budgets'), isEmpty);
    });

    test('is not asked for before the customer is signed in', () async {
      final notifications = FakeNotificationService();
      final container = makeContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(FakeSessionStore()),
          httpClientAdapterProvider.overrideWithValue(FakeApi()),
          clockProvider.overrideWithValue(() => _now),
          notificationServiceProvider.overrideWithValue(notifications),
          alertDedupeStoreProvider.overrideWithValue(FakeAlertDedupeStore()),
        ],
      );
      readAndKeepAlive(container, budgetAlertsProvider);

      expect(
        await container.read(notificationsAllowedProvider.future),
        isFalse,
      );
      expect(notifications.initialiseCount, 0);
    });
  });

  group('the alert itself', () {
    test('names the category from its id when nothing has fetched the list',
        () async {
      final notifications = FakeNotificationService();
      final store = FakeAlertDedupeStore();
      final api = FakeApi();
      _budgets(api, _food(400000));

      final container =
          _container(api, notifications: notifications, store: store);
      await _settle(container);

      expect(notifications.shown.single.title, contains('Food'));
      // A notification is not worth a network request of its own.
      expect(api.requestsFor('GET', '/categories'), isEmpty);
    });

    test('keeps the same id for the same alert from one run to the next', () {
      expect(
        notificationIdFor(
          alertKey(month: _month, category: 'food', threshold: 80),
        ),
        notificationIdFor('2026-09|food|80'),
      );
      expect(
        notificationIdFor('2026-09|food|80'),
        isNot(notificationIdFor('2026-09|food|100')),
      );
      expect(notificationIdFor('2026-09|food|80'), lessThan(1 << 31));
    });
  });

  group('the dedupe store on disk', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('spendwise_alerts_test');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    FileAlertDedupeStore store() =>
        FileAlertDedupeStore(directory: () async => directory);

    File file() => File('${directory.path}/${FileAlertDedupeStore.fileName}');

    test('a key fired before the app restarted is still fired', () async {
      expect(await store().markFired('2026-09|food|80'), isTrue);

      // A second store over the same directory is the next launch.
      final next = store();
      expect(await next.markFired('2026-09|food|80'), isFalse);
      expect(await next.fired(), {'2026-09|food|80'});
    });

    test('two alerts landing together are decided one at a time', () async {
      final subject = store();

      final answers = await Future.wait([
        subject.markFired('2026-09|food|80'),
        subject.markFired('2026-09|food|80'),
        subject.markFired('2026-09|food|100'),
      ]);

      expect(answers.where((isNew) => isNew), hasLength(2));
      expect(await subject.fired(), {'2026-09|food|80', '2026-09|food|100'});
    });

    test('only the newest three months are kept', () async {
      final subject = store();
      for (final month in ['2026-06', '2026-07', '2026-08', '2026-09']) {
        await subject.markFired('$month|food|80');
      }

      // June is past the window, so its key can never be consulted again and
      // is not worth carrying.
      expect(await subject.fired(), {
        '2026-07|food|80',
        '2026-08|food|80',
        '2026-09|food|80',
      });
      expect(await store().fired(), hasLength(3));
    });

    test('a file that cannot be read is an empty set, not a crash', () async {
      await store().markFired('2026-09|food|80');
      file().writeAsStringSync('{ not a list');

      final subject = store();

      expect(await subject.fired(), isEmpty);
      // And it recovers: the next alert is recorded over the wreckage.
      expect(await subject.markFired('2026-09|food|80'), isTrue);
      expect(jsonDecode(file().readAsStringSync()), ['2026-09|food|80']);
    });

    test('keys that are not ours are dropped rather than trusted', () async {
      file().writeAsStringSync(jsonEncode(['nonsense', '2026-09|food|80']));

      expect(await store().fired(), {'2026-09|food|80'});
    });

    test('clearing forgets everything, on disk too', () async {
      final subject = store();
      await subject.markFired('2026-09|food|80');

      await subject.clear();

      expect(await subject.fired(), isEmpty);
      expect(file().existsSync(), isFalse);
      expect(await store().markFired('2026-09|food|80'), isTrue);
    });
  });

  group('crossedThresholds', () {
    test('answers in integers, at the same 80% the badge turns amber', () {
      expect(
        crossedThresholds(spentPaise: 399999, limitPaise: 500000),
        isEmpty,
      );
      expect(crossedThresholds(spentPaise: 400000, limitPaise: 500000), [80]);
      expect(crossedThresholds(spentPaise: 499999, limitPaise: 500000), [80]);
      expect(
        crossedThresholds(spentPaise: 500000, limitPaise: 500000),
        [80, 100],
      );
    });

    test('a limit of zero is not a budget to alert on', () {
      expect(crossedThresholds(spentPaise: 100000, limitPaise: 0), isEmpty);
      expect(usedPercent(spentPaise: 100000, limitPaise: 0), 0);
    });
  });
}
