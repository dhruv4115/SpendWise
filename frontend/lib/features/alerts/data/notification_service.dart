/// The one place that talks to flutter_local_notifications.
///
/// Everything here is best-effort. A customer who has refused notifications,
/// a device that has them switched off, and a widget test with no plugin
/// behind the method channel all end up in the same place: [initialise]
/// answers false, [show] does nothing, and the rest of the app carries on
/// exactly as it did.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The only channel this app creates. One channel, so a customer who mutes
/// budget alerts mutes all of them and keeps whatever else may be added
/// later.
const String budgetAlertsChannelId = 'budget_alerts';
const String budgetAlertsChannelName = 'Budget alerts';
const String budgetAlertsChannelDescription =
    'Tells you when a category is close to its monthly limit, or past it.';

/// The Android notification icon. The launcher icon until the app has a
/// proper monochrome one.
const String _androidIcon = '@mipmap/ic_launcher';

/// What a tapped notification carries back. Never an identifier — see
/// [NotificationService.show].
typedef NotificationTapCallback = void Function(String payload);

/// Posting a notification, as its callers see it.
abstract interface class NotificationService {
  /// Creates the channel and asks for permission, once.
  ///
  /// Answers whether the app may post notifications at all. Safe to call
  /// again: the same answer comes back without a second prompt.
  ///
  /// [onTap] is called with the notification's payload when the customer taps
  /// one while the app is running.
  Future<bool> initialise({required NotificationTapCallback onTap});

  /// Posts one notification, replacing any earlier one with the same [id].
  ///
  /// A no-op when notifications are not allowed. [payload] is routing
  /// information and nothing else: it must never carry an account number or
  /// a transaction id, because the operating system keeps it.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  /// The payload of the notification the app was started by tapping, or null
  /// when it was started some other way.
  Future<String?> launchPayload();
}

/// A notification id derived from [seed], so the same alert replaces itself
/// rather than stacking up.
///
/// FNV-1a folded into 31 bits: `String.hashCode` is not promised to be the
/// same from one run to the next, and an id that changed on restart would let
/// one alert appear twice.
int notificationIdFor(String seed) {
  var hash = 0x811c9dc5;
  for (final unit in seed.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// The real thing, on Android and iOS.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The one initialisation, shared by every caller that awaits it.
  Future<bool>? _ready;

  @override
  Future<bool> initialise({required NotificationTapCallback onTap}) =>
      _ready ??= _initialise(onTap);

  Future<bool> _initialise(NotificationTapCallback onTap) async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_androidIcon),
          // Asked for explicitly below instead, so the prompt appears at the
          // same point in the app's life on both platforms.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) onTap(payload);
        },
      );
      return await _requestPermission();
    } on Object {
      // No plugin behind the channel — a test, or a platform this app does
      // not post notifications on.
      return false;
    }
  }

  /// Asks the platform, and takes no for an answer.
  Future<bool> _requestPermission() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (android == null) return false;
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            budgetAlertsChannelId,
            budgetAlertsChannelName,
            description: budgetAlertsChannelDescription,
            importance: Importance.high,
          ),
        );
        // Android 13 and newer prompt; older versions answer true without
        // one. A null means the platform did not say, so ask it what it
        // already allows rather than assuming either way.
        return await android.requestNotificationsPermission() ??
            await android.areNotificationsEnabled() ??
            false;

      case TargetPlatform.iOS:
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        if (ios == null) return false;
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;

      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false;
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final allowed = await (_ready ?? Future<bool>.value(false));
    if (!allowed) return;

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            budgetAlertsChannelId,
            budgetAlertsChannelName,
            channelDescription: budgetAlertsChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            // The body is a sentence, not a line: expanded, it is read in
            // full rather than cut off at the notification's width.
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } on Object {
      // A notification that cannot be posted is not worth an error on screen.
    }
  }

  @override
  Future<String?> launchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      final payload = details.notificationResponse?.payload;
      return payload == null || payload.isEmpty ? null : payload;
    } on Object {
      return null;
    }
  }
}

/// The app's notification service. Overridden in tests with a recorder.
final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>((ref) => LocalNotificationService());
