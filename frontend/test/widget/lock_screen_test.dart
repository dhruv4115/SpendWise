import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/core/security/biometric_service.dart';
import 'package:spendwise/features/auth/state/session_provider.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';

import '../helpers/categories.dart';
import '../helpers/fake_api.dart';
import '../helpers/fake_biometrics.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/summaries.dart';
import '../helpers/test_app.dart';
import '../helpers/transactions.dart';

final DateTime _now = DateTime(2026, 9, 23, 12);

/// Enough of the API for the Overview tab, which is where a signed-in
/// customer lands before the app is locked behind them.
FakeApi _api() => FakeApi()
  ..on('GET', '/categories', body: categoriesWire())
  ..on('GET', '/summary', body: septemberWire())
  ..on('GET', '/transactions', body: pageWire([txnWire()]));

/// Signs in, lands on Overview, then locks the app — the sequence that puts
/// the lock screen up in the real app.
Future<TestHarness> _lockedApp(
  WidgetTester tester,
  FakeBiometricService biometrics,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final harness = routedApp(
    _api(),
    store: FakeSessionStore(session: testSession),
    initialLocation: Routes.overviewPath,
    overrides: [
      clockProvider.overrideWithValue(() => _now),
      biometricServiceProvider.overrideWithValue(biometrics),
    ],
  );
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  expect(harness.location, Routes.overviewPath);

  harness.container.read(sessionProvider.notifier).lock();
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('a locked session is sent to the lock screen', (tester) async {
    final harness = await _lockedApp(
      tester,
      FakeBiometricService(outcome: UnlockOutcome.refused),
    );

    expect(harness.location, Routes.lockPath);
    expect(find.text('Unlock SpendWise'), findsOneWidget);
    // Nothing behind the lock is on show: not the balance, not the customer.
    expect(find.textContaining('Asha'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
  });

  testWidgets('the device is asked as soon as the screen appears', (
    tester,
  ) async {
    final biometrics = FakeBiometricService(outcome: UnlockOutcome.refused);
    await _lockedApp(tester, biometrics);

    expect(biometrics.promptCount, 1);
    expect(biometrics.prompts.single, contains('SpendWise'));
  });

  testWidgets('a failed check leaves the app locked and offers another go', (
    tester,
  ) async {
    final biometrics = FakeBiometricService(outcome: UnlockOutcome.refused);
    final harness = await _lockedApp(tester, biometrics);

    expect(harness.container.read(sessionProvider), isA<SessionLocked>());
    expect(harness.location, Routes.lockPath);
    expect(
      find.text(
        'We could not confirm it was you. Try again, or log out and sign in '
        'with your password.',
      ),
      findsOneWidget,
    );
    // The button now says what pressing it would do.
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsNothing);
  });

  testWidgets('the retry can succeed, and the app opens where it was', (
    tester,
  ) async {
    // Refused on the automatic prompt, accepted when they press Try again.
    final biometrics = FakeBiometricService(
      outcomes: const [UnlockOutcome.refused],
    );
    final harness = await _lockedApp(tester, biometrics);

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pumpAndSettle();

    expect(biometrics.promptCount, 2);
    expect(harness.container.read(sessionProvider), isA<SessionSignedIn>());
    expect(harness.location, Routes.overviewPath);
  });

  testWidgets('a device with nothing enrolled says so, plainly', (
    tester,
  ) async {
    final biometrics = FakeBiometricService(outcome: UnlockOutcome.notEnrolled);
    await _lockedApp(tester, biometrics);

    expect(
      find.textContaining('no fingerprint, face or screen lock set up'),
      findsOneWidget,
    );
    expect(find.text('Log out instead'), findsOneWidget);
  });

  testWidgets('Log out instead signs out and returns to sign-in', (
    tester,
  ) async {
    final biometrics = FakeBiometricService(outcome: UnlockOutcome.refused);
    final harness = await _lockedApp(tester, biometrics);

    await tester.tap(find.text('Log out instead'));
    await tester.pumpAndSettle();

    expect(harness.container.read(sessionProvider), isA<SessionSignedOut>());
    expect(harness.store.stored, isNull);
    expect(harness.location, Routes.loginPath);
  });

  testWidgets('does not overflow at textScaler 2.0 on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = routedApp(
      _api(),
      store: FakeSessionStore(session: testSession),
      initialLocation: Routes.overviewPath,
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        biometricServiceProvider.overrideWithValue(
          FakeBiometricService(outcome: UnlockOutcome.notEnrolled),
        ),
      ],
    );
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(tester.view)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: harness.app,
      ),
    );
    await tester.pumpAndSettle();
    harness.container.read(sessionProvider.notifier).lock();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Unlock SpendWise'), findsOneWidget);
  });
}
