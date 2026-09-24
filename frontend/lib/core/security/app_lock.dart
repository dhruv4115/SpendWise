/// The app lock: away means locked, and coming back means proving who you
/// are.
///
/// The lock itself is a session state — [SessionLocked] — so the router is
/// what puts the lock screen up, exactly as it is what puts the sign-in screen
/// up. This file is the part that watches the app's lifecycle and decides
/// when that state changes.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/session_provider.dart';
import '../utils/clock.dart';
import 'biometric_service.dart';

/// How long the app may be away before coming back means unlocking it.
///
/// Backgrounding is not always the customer leaving: a permission dialog, a
/// biometric prompt and the share sheet all pause the app for a second or
/// two. Locking regardless — and then asking for a fingerprint to get back to
/// the screen they never left — trains people to hate the lock. Ten seconds
/// is long enough for every system dialog and far too short to hand someone
/// else an unlocked phone.
const Duration lockGrace = Duration(seconds: 10);

/// What the lock is doing.
@immutable
class AppLockState {
  const AppLockState({
    this.awaySince,
    this.isAuthenticating = false,
    this.lastOutcome,
  });

  static const AppLockState idle = AppLockState();

  /// When the app went to the background, or null while it is in front.
  final DateTime? awaySince;

  /// Whether the device's prompt is up right now.
  final bool isAuthenticating;

  /// How the last unlock attempt ended, so the lock screen can say. Null
  /// before the first attempt of this lock.
  final UnlockOutcome? lastOutcome;

  bool get isAway => awaySince != null;

  AppLockState copyWith({
    Object? awaySince = _unset,
    bool? isAuthenticating,
    Object? lastOutcome = _unset,
  }) {
    return AppLockState(
      awaySince: identical(awaySince, _unset)
          ? this.awaySince
          : awaySince as DateTime?,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      lastOutcome: identical(lastOutcome, _unset)
          ? this.lastOutcome
          : lastOutcome as UnlockOutcome?,
    );
  }

  @override
  String toString() => 'AppLockState(away: $isAway, '
      'authenticating: $isAuthenticating, last: ${lastOutcome?.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppLockState &&
          other.awaySince == awaySince &&
          other.isAuthenticating == isAuthenticating &&
          other.lastOutcome == lastOutcome;

  @override
  int get hashCode => Object.hash(awaySince, isAuthenticating, lastOutcome);
}

/// Distinguishes "leave the field alone" from "clear it" in [copyWith].
const Object _unset = Object();

/// Locks the app when it goes away, and opens it when the customer proves
/// who they are.
///
/// It locks on the way out rather than on the way back, so the window is
/// already showing the lock screen when the operating system takes its
/// snapshot for the recents list — one of the two places a balance leaks, the
/// other being a screenshot, which `SecureScreen` covers.
class AppLockController extends Notifier<AppLockState>
    with WidgetsBindingObserver {
  /// Stops a second prompt while the first is still up: the lock screen asks
  /// automatically when it appears, and the customer may also press Unlock.
  bool _authenticating = false;

  @override
  AppLockState build() {
    final binding = WidgetsBinding.instance..addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    return AppLockState.idle;
  }

  DateTime get _now => ref.read(clockProvider)();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // inactive comes first on both platforms — for the app switcher, and
      // for a system dialog taking focus. Both are "not in front of the
      // customer", which is all the lock cares about.
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        wentAway();
      case AppLifecycleState.resumed:
        cameBack();
      case AppLifecycleState.detached:
        // The engine is going; there is no window left to protect.
        break;
    }
  }

  /// The app left the foreground. Locks a signed-in session and notes when.
  @visibleForTesting
  void wentAway() {
    if (state.isAway) return; // inactive, then paused: one departure.
    if (ref.read(sessionProvider) is! SessionSignedIn) return;

    state = AppLockState(awaySince: _now);
    ref.read(sessionProvider.notifier).lock();
  }

  /// The app came back.
  ///
  /// Inside the grace period this undoes the lock without asking: the
  /// customer never really left. Past it, the session stays locked and the
  /// router has already put the lock screen up.
  @visibleForTesting
  void cameBack() {
    final awaySince = state.awaySince;
    state = state.copyWith(awaySince: null);
    if (awaySince == null) return;

    final away = _now.difference(awaySince);
    if (away < lockGrace && ref.read(sessionProvider) is SessionLocked) {
      ref.read(sessionProvider.notifier).unlock();
    }
  }

  /// Asks the device to confirm who is holding the phone, and unlocks on a
  /// yes.
  ///
  /// Never throws: the outcome is both returned and left in [state] for the
  /// lock screen to explain.
  Future<UnlockOutcome> unlock() async {
    if (_authenticating) return UnlockOutcome.refused;
    _authenticating = true;
    state = state.copyWith(isAuthenticating: true, lastOutcome: null);

    final outcome = await ref.read(biometricServiceProvider).authenticate(
          reason: 'Unlock SpendWise to see your spending',
        );

    _authenticating = false;
    state = state.copyWith(isAuthenticating: false, lastOutcome: outcome);
    if (outcome.isUnlocked) ref.read(sessionProvider.notifier).unlock();
    return outcome;
  }

  /// The way out for a customer who cannot unlock: sign out and sign back in
  /// with an email and a password.
  Future<void> signOut() async {
    state = AppLockState.idle;
    await ref.read(sessionProvider.notifier).signOut();
  }
}

final NotifierProvider<AppLockController, AppLockState> appLockProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);
