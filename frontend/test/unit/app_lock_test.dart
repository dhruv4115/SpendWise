import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/security/app_lock.dart';
import 'package:spendwise/core/security/biometric_service.dart';
import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/core/utils/clock.dart';
import 'package:spendwise/features/auth/state/session_provider.dart';

import '../helpers/container.dart';
import '../helpers/fake_biometrics.dart';
import '../helpers/fake_session_store.dart';

/// The clock the app lock reads. Moved by [_wait].
late DateTime _now;

void _wait(Duration elapsed) => _now = _now.add(elapsed);

ProviderContainer _container({
  FakeSessionStore? store,
  FakeBiometricService? biometrics,
}) {
  return makeContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(
        store ?? FakeSessionStore(session: testSession),
      ),
      clockProvider.overrideWithValue(() => _now),
      biometricServiceProvider
          .overrideWithValue(biometrics ?? FakeBiometricService()),
    ],
  );
}

/// A container with the lock running and the session restored from the store,
/// which is where every one of these tests starts.
Future<ProviderContainer> _signedIn({
  FakeSessionStore? store,
  FakeBiometricService? biometrics,
}) async {
  final container = _container(store: store, biometrics: biometrics);
  readAndKeepAlive(container, appLockProvider);
  readAndKeepAlive(container, sessionProvider);
  // The session is read from the keystore on boot.
  await container.read(sessionProvider.notifier).restore();
  return container;
}

AppLockController _lock(ProviderContainer container) =>
    container.read(appLockProvider.notifier);

SessionState _session(ProviderContainer container) =>
    container.read(sessionProvider);

void main() {
  // The controller registers itself with the binding, which has to exist.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => _now = DateTime(2026, 9, 23, 12));

  group('going away', () {
    test('locks a signed-in session and remembers when', () async {
      final container = await _signedIn();
      expect(_session(container), isA<SessionSignedIn>());

      _lock(container).wentAway();

      expect(_session(container), isA<SessionLocked>());
      // The token is kept: this is a lock, not a sign-out.
      expect(_session(container).session, testSession);
      expect(container.read(appLockProvider).awaySince, _now);
    });

    test('is what the lifecycle observer does with a real event', () async {
      final container = await _signedIn();

      // Through the binding, so the observer really is registered.
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);

      expect(_session(container), isA<SessionLocked>());
    });

    test('leaves a signed-out app alone', () async {
      final container = await _signedIn(store: FakeSessionStore());
      expect(_session(container), isA<SessionSignedOut>());

      _lock(container).wentAway();

      expect(_session(container), isA<SessionSignedOut>());
      expect(container.read(appLockProvider).awaySince, isNull);
    });

    test('inactive then paused is one departure, timed from the first',
        () async {
      final container = await _signedIn();
      final leftAt = _now;

      // iOS sends inactive as the switcher opens, paused a moment later.
      _lock(container).wentAway();
      _wait(const Duration(seconds: 2));
      _lock(container).wentAway();

      expect(container.read(appLockProvider).awaySince, leftAt);
    });
  });

  group('coming back', () {
    test('inside the grace period unlocks without asking', () async {
      final biometrics = FakeBiometricService();
      final container = await _signedIn(biometrics: biometrics);

      // A permission dialog: away for a moment, and back.
      _lock(container).wentAway();
      _wait(const Duration(seconds: 5));
      _lock(container).cameBack();

      expect(_session(container), isA<SessionSignedIn>());
      expect(container.read(appLockProvider).awaySince, isNull);
      // Nobody was asked for a fingerprint to get back to a screen they
      // never left.
      expect(biometrics.promptCount, 0);
    });

    test('at the very edge of the grace period still unlocks', () async {
      final container = await _signedIn();

      _lock(container).wentAway();
      _wait(lockGrace - const Duration(milliseconds: 1));
      _lock(container).cameBack();

      expect(_session(container), isA<SessionSignedIn>());
    });

    test('after the grace period leaves it locked', () async {
      final container = await _signedIn();

      _lock(container).wentAway();
      _wait(lockGrace + const Duration(seconds: 1));
      _lock(container).cameBack();

      expect(_session(container), isA<SessionLocked>());
      expect(container.read(appLockProvider).awaySince, isNull);
    });

    test('does not unlock a session that was signed out while away', () async {
      final container = await _signedIn();

      _lock(container).wentAway();
      await container.read(sessionProvider.notifier).signOut();
      _wait(const Duration(seconds: 1));
      _lock(container).cameBack();

      expect(_session(container), isA<SessionSignedOut>());
    });

    test('without having gone away changes nothing', () async {
      final container = await _signedIn();

      _lock(container).cameBack();

      expect(_session(container), isA<SessionSignedIn>());
    });
  });

  group('unlocking', () {
    test('a confirmed identity opens the app', () async {
      final biometrics = FakeBiometricService();
      final container = await _signedIn(biometrics: biometrics);
      _lock(container).wentAway();
      _wait(lockGrace * 2);
      _lock(container).cameBack();

      final outcome = await _lock(container).unlock();

      expect(outcome, UnlockOutcome.unlocked);
      expect(_session(container), isA<SessionSignedIn>());
      expect(biometrics.promptCount, 1);
      expect(container.read(appLockProvider).isAuthenticating, isFalse);
    });

    test('a refusal leaves it locked, and says so', () async {
      final biometrics = FakeBiometricService(outcome: UnlockOutcome.refused);
      final container = await _signedIn(biometrics: biometrics);
      _lock(container).wentAway();

      final outcome = await _lock(container).unlock();

      expect(outcome, UnlockOutcome.refused);
      expect(_session(container), isA<SessionLocked>());
      expect(
          container.read(appLockProvider).lastOutcome, UnlockOutcome.refused);
    });

    test('a device that cannot be asked is reported, not thrown', () async {
      final biometrics =
          FakeBiometricService(outcome: UnlockOutcome.notEnrolled);
      final container = await _signedIn(biometrics: biometrics);
      _lock(container).wentAway();

      final outcome = await _lock(container).unlock();

      expect(outcome, UnlockOutcome.notEnrolled);
      expect(outcome.canTryAgain, isFalse);
      expect(_session(container), isA<SessionLocked>());
    });

    test('two taps do not put up two prompts', () async {
      final biometrics = FakeBiometricService();
      final container = await _signedIn(biometrics: biometrics);
      _lock(container).wentAway();

      // The screen asks as it appears; the customer presses Unlock as well.
      await Future.wait([_lock(container).unlock(), _lock(container).unlock()]);

      expect(biometrics.promptCount, 1);
    });
  });

  group('logging out instead', () {
    test('clears the session and the keystore', () async {
      final store = FakeSessionStore(session: testSession);
      final container = await _signedIn(store: store);
      _lock(container).wentAway();

      await _lock(container).signOut();

      expect(_session(container), isA<SessionSignedOut>());
      expect(store.stored, isNull);
      expect(store.clearCount, 1);
      expect(container.read(appLockProvider), AppLockState.idle);
    });
  });
}
