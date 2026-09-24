import 'package:spendwise/features/alerts/data/alert_dedupe_store.dart';
import 'package:spendwise/features/alerts/data/notification_service.dart';

/// A notification the app asked for.
class ShownNotification {
  const ShownNotification({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });

  final int id;
  final String title;
  final String body;
  final String? payload;

  @override
  String toString() => 'ShownNotification($title)';
}

/// Records what would have been posted, and lets a test answer for the
/// platform's permission prompt.
class FakeNotificationService implements NotificationService {
  FakeNotificationService({this.allowed = true, this.launchedWith});

  /// What the permission prompt answers.
  final bool allowed;

  /// The payload the app was started by tapping, if any.
  final String? launchedWith;

  final List<ShownNotification> shown = [];

  int initialiseCount = 0;

  /// The callback the app registered, so a test can play a tap through it.
  NotificationTapCallback? onTap;

  /// The titles posted, in order — the usual assertion.
  List<String> get titles => [for (final one in shown) one.title];

  @override
  Future<bool> initialise({required NotificationTapCallback onTap}) async {
    initialiseCount += 1;
    this.onTap = onTap;
    return allowed;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!allowed) return;
    shown.add(
      ShownNotification(id: id, title: title, body: body, payload: payload),
    );
  }

  @override
  Future<String?> launchPayload() async => launchedWith;
}

/// The dedupe store without a disk behind it. Same contract: [markFired]
/// answers true exactly once per key.
class FakeAlertDedupeStore implements AlertDedupeStore {
  FakeAlertDedupeStore({Set<String> seed = const {}}) : keys = {...seed};

  final Set<String> keys;

  @override
  Future<bool> markFired(String key) async => keys.add(key);

  @override
  Future<Set<String>> fired() async => Set.unmodifiable(keys);

  @override
  Future<void> clear() async => keys.clear();
}
