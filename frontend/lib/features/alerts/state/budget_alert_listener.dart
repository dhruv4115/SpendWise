/// Watches the current month's budgets for the whole session and tells the
/// customer, once, when a category passes 80% or 100% of its limit.
///
/// Wired in `app.dart` rather than on a screen: an alert about the food
/// budget is no use only to a customer who happens to be looking at the
/// Budgets tab.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// The router is the app's, not this feature's. It is read lazily, inside a
// tap handler, so nothing here builds a route or depends on one existing.
import '../../../app/router.dart';
import '../../../app/routes.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/money.dart';
import '../../auth/state/session_provider.dart';
import '../../budgets/data/budget_risk.dart';
import '../../budgets/state/budgets_provider.dart';
import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../../transactions/state/month_provider.dart';
import '../data/alert_dedupe_store.dart';
import '../data/notification_service.dart';

/// Where an alert is raised, as whole percentages of the limit.
///
/// The first is the same number that turns a budget card amber, taken from
/// [warningPercent] rather than written again, so a customer cannot see the
/// amber badge without the alert or the other way round.
const List<int> alertThresholds = <int>[warningPercent, 100];

/// Which of [alertThresholds] a spend of [spentPaise] has reached against
/// [limitPaise], lowest first.
///
/// Cross-multiplied rather than divided, like [riskFor]: integer maths only,
/// and no rounding to argue with. A category whose refunds outweigh its
/// spends has crossed nothing, and a limit of zero is not a budget to alert
/// on — there is no percentage of it to report.
List<int> crossedThresholds({
  required int spentPaise,
  required int limitPaise,
}) {
  if (spentPaise <= 0 || limitPaise <= 0) return const <int>[];
  return <int>[
    for (final threshold in alertThresholds)
      if (spentPaise * 100 >= limitPaise * threshold) threshold,
  ];
}

/// How much of the limit is gone, as a whole percentage, floored.
int usedPercent({required int spentPaise, required int limitPaise}) {
  if (spentPaise <= 0 || limitPaise <= 0) return 0;
  return spentPaise * 100 ~/ limitPaise;
}

/// `2026-09|food` — what a tapped alert opens.
///
/// Routing information and nothing else. The operating system keeps a
/// payload for as long as the notification exists, so no identifier and no
/// amount ever goes in one.
String alertPayload({required String month, required String category}) =>
    '$month|$category';

final RegExp _payloadPattern = RegExp(r'^(\d{4}-\d{2})\|([a-z0-9_-]{1,40})$');

/// Whether the app may post notifications at all, asked once per session.
///
/// Nothing is asked of the customer before they are signed in: a permission
/// prompt over the sign-in screen is a prompt about an app they have not seen
/// yet. Returning false is a perfectly good answer — [budgetAlertsProvider]
/// then leaves the budgets alone, and the app is otherwise unchanged.
final FutureProvider<bool> notificationsAllowedProvider =
    FutureProvider<bool>((ref) async {
  final signedIn = ref.watch(
    sessionProvider.select((state) => state.session != null),
  );
  if (!signedIn) return false;

  final service = ref.watch(notificationServiceProvider);
  final allowed = await service.initialise(
    onTap: (payload) => _openBudget(ref, payload),
  );
  if (!allowed) return false;

  // The app was started by tapping an alert while it was not running.
  final launched = await service.launchPayload();
  if (launched != null) _openBudget(ref, launched);
  return true;
});

/// Opens `/budgets/:category` for the month the alert was about.
///
/// The month goes first: a customer browsing July who is told about September
/// should land on September's budget, not on July's under a September
/// headline. Anything that is not one of our own payloads is ignored.
void _openBudget(Ref ref, String payload) {
  final match = _payloadPattern.firstMatch(payload);
  if (match == null) return;

  ref.read(monthProvider.notifier).set(match.group(1)!);
  ref.read(routerProvider).go(Routes.budgetDetail(match.group(2)!));
}

/// The listener itself: one month's budgets in, at most one notification per
/// category per threshold out.
///
/// Every decision is made through the dedupe store, which is on disk, so
/// "have I already said this?" survives a restart and is not a field on this
/// object.
class BudgetAlerts {
  BudgetAlerts({
    required this.month,
    required AlertDedupeStore store,
    required NotificationService notifications,
    required String Function(String category) categoryName,
  })  : _store = store,
        _notifications = notifications,
        _categoryName = categoryName;

  /// `YYYY-MM`, the month being watched.
  final String month;

  final AlertDedupeStore _store;
  final NotificationService _notifications;
  final String Function(String category) _categoryName;

  /// Alerts are decided one after another, never at the same time: two
  /// refreshes landing together must not both find the same key unfired.
  Future<void> _queue = Future<void>.value();

  bool _disposed = false;

  /// Completes when everything the listener has been handed has been decided.
  ///
  /// The seam a test waits on instead of guessing at a delay.
  Future<void> get settled => _queue;

  /// A new reading of the month's budgets.
  void onBudgets(AsyncValue<List<BudgetView>> budgets) {
    final rows = budgets.valueOrNull;
    if (_disposed || rows == null || rows.isEmpty) return;
    _queue = _queue.then((_) => _evaluate(rows));
  }

  void dispose() => _disposed = true;

  Future<void> _evaluate(List<BudgetView> rows) async {
    if (_disposed) return;

    for (final row in rows) {
      final crossed = crossedThresholds(
        spentPaise: row.spentPaise,
        limitPaise: row.limitPaise,
      );

      // Every threshold reached is recorded, but only the highest new one is
      // announced: a budget that arrives already spent deserves one alert
      // saying so, not one for each line it has passed.
      var highest = 0;
      for (final threshold in crossed) {
        final key = alertKey(
          month: month,
          category: row.category,
          threshold: threshold,
        );
        try {
          if (await _store.markFired(key) && threshold > highest) {
            highest = threshold;
          }
        } on Object {
          // A store that cannot answer is not a reason to alert twice.
          return;
        }
      }
      if (highest == 0 || _disposed) continue;

      await _fire(row, highest);
    }
  }

  Future<void> _fire(BudgetView row, int threshold) async {
    try {
      final name = _categoryName(row.category);
      final percent = usedPercent(
        spentPaise: row.spentPaise,
        limitPaise: row.limitPaise,
      );

      await _notifications.show(
        id: notificationIdFor(
          alertKey(month: month, category: row.category, threshold: threshold),
        ),
        title: threshold >= 100
            ? 'You have used up your $name budget'
            : 'You are nearing your $name budget',
        // The category and the percentage, and nothing that identifies an
        // account: a notification is read off a locked phone.
        body: '$name is at $percent% of its ${formatPaise(row.limitPaise)} '
            'limit for ${monthKeyLabel(month)}.',
        payload: alertPayload(month: month, category: row.category),
      );
    } on Object {
      // Already recorded as fired: a notification the platform refused is
      // not worth pestering the customer with on the next refresh either.
    }
  }
}

/// The session-long listener. Watched once, in `app.dart`.
///
/// It subscribes to the budgets only when there is somewhere for an alert to
/// go — signed in, and notifications allowed. A customer who has refused them
/// is not worth a month's budgets being fetched and refetched in the
/// background for the rest of the session.
final Provider<BudgetAlerts> budgetAlertsProvider = Provider<BudgetAlerts>(
  (ref) {
    final month = ref.watch(latestMonthProvider);

    final alerts = BudgetAlerts(
      month: month,
      store: ref.watch(alertDedupeStoreProvider),
      notifications: ref.watch(notificationServiceProvider),
      // Read when the alert fires, from the list the rest of the app is
      // already using, and only if something has already fetched it: a
      // notification is not worth a network request, and a category id reads
      // well enough without one.
      categoryName: (category) => (ref.exists(categoriesProvider)
              ? ref.read(categoriesProvider).valueOrNull ?? const <Category>[]
              : const <Category>[])
          .nameOf(category),
    );
    ref.onDispose(alerts.dispose);

    final signedIn = ref.watch(
      sessionProvider.select((state) => state.session != null),
    );
    final allowed =
        ref.watch(notificationsAllowedProvider).valueOrNull ?? false;
    if (!signedIn || !allowed) return alerts;

    ref.listen<AsyncValue<List<BudgetView>>>(
      budgetsProvider(month),
      (_, next) => alerts.onBudgets(next),
      fireImmediately: true,
    );
    return alerts;
  },
);
