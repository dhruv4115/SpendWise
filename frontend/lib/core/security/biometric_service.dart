/// The device asking the customer to prove it is them — Face ID, a
/// fingerprint, or the screen lock behind them.
///
/// Everything the plugin can throw is caught here and answered as an
/// [UnlockOutcome]. A lock screen has to say something useful when the sensor
/// is busy or the customer has no fingerprints enrolled, and it cannot do that
/// from a stack trace.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// What came of asking.
enum UnlockOutcome {
  /// Identity confirmed. The only outcome that opens the app.
  unlocked,

  /// The prompt ran and did not confirm: the wrong finger, or the customer
  /// dismissed it. Trying again is reasonable.
  refused,

  /// There is no way to show the prompt on this device — no biometric
  /// hardware, or none available just now.
  notAvailable,

  /// The device could authenticate, but nothing is set up to authenticate
  /// with: no biometrics enrolled and no screen lock behind them.
  notEnrolled,

  /// Too many failed attempts; the platform has closed the door for now.
  lockedOut,

  /// Anything else the platform reported.
  failed;

  bool get isUnlocked => this == UnlockOutcome.unlocked;

  /// Whether pressing Unlock again could plausibly work. False when the
  /// device itself is the problem: the way out then is to sign in again.
  bool get canTryAgain => switch (this) {
        UnlockOutcome.unlocked => false,
        UnlockOutcome.notAvailable => false,
        UnlockOutcome.notEnrolled => false,
        UnlockOutcome.lockedOut => false,
        UnlockOutcome.refused => true,
        UnlockOutcome.failed => true,
      };
}

/// The device's own authentication, as its callers see it.
abstract interface class BiometricService {
  /// Whether the device has biometric hardware this app can check.
  Future<bool> canCheckBiometrics();

  /// Whether the device can authenticate at all — biometrics, or the PIN,
  /// pattern or passcode they fall back to.
  Future<bool> isDeviceSupported();

  /// Shows the prompt. Never throws.
  Future<UnlockOutcome> authenticate({required String reason});
}

/// local_auth, wrapped.
class LocalAuthBiometricService implements BiometricService {
  LocalAuthBiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<UnlockOutcome> authenticate({required String reason}) async {
    try {
      // local_auth 3 builds the options object itself: these two named
      // arguments are exactly `AuthenticationOptions(biometricOnly: false,
      // stickyAuth: true)`. biometricOnly false is what lets the device PIN
      // stand in for a finger; stickyAuth is what stops the prompt failing
      // outright when the system briefly backgrounds the app to show it.
      final unlocked = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return unlocked ? UnlockOutcome.unlocked : UnlockOutcome.refused;
    } on LocalAuthException catch (error) {
      return _outcomeOf(error.code);
    } on Object {
      // A plugin that is not there at all — a test, or a desktop build.
      return UnlockOutcome.notAvailable;
    }
  }

  /// The plugin's codes, in the three groups a lock screen can say something
  /// about. The enum is explicitly open-ended, so anything unrecognised is
  /// [UnlockOutcome.failed] rather than a crash.
  static UnlockOutcome _outcomeOf(LocalAuthExceptionCode code) {
    return switch (code) {
      LocalAuthExceptionCode.noBiometricHardware ||
      LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
      LocalAuthExceptionCode.uiUnavailable =>
        UnlockOutcome.notAvailable,
      LocalAuthExceptionCode.noBiometricsEnrolled ||
      LocalAuthExceptionCode.noCredentialsSet =>
        UnlockOutcome.notEnrolled,
      LocalAuthExceptionCode.temporaryLockout ||
      LocalAuthExceptionCode.biometricLockout =>
        UnlockOutcome.lockedOut,
      LocalAuthExceptionCode.userCanceled ||
      LocalAuthExceptionCode.systemCanceled ||
      LocalAuthExceptionCode.timeout ||
      LocalAuthExceptionCode.userRequestedFallback ||
      LocalAuthExceptionCode.authInProgress =>
        UnlockOutcome.refused,
      _ => UnlockOutcome.failed,
    };
  }
}

/// The app's biometric service. Overridden in tests.
final Provider<BiometricService> biometricServiceProvider =
    Provider<BiometricService>((ref) => LocalAuthBiometricService());
