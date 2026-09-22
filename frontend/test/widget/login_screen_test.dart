import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/test_app.dart';

const String _email = 'asha@example.com';
const String _password = 'password123';

Finder get _emailField => find.widgetWithText(TextFormField, 'Email address');
Finder get _passwordField => find.widgetWithText(TextFormField, 'Password');
Finder get _submit => find.widgetWithText(FilledButton, 'Sign in');

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(_emailField, _email);
  await tester.enterText(_passwordField, _password);
  // At a large text scale the button is below the fold; scroll to it exactly
  // as a customer would have to.
  await tester.ensureVisible(_submit);
  await tester.pumpAndSettle();
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

void main() {
  group('LoginScreen', () {
    testWidgets('an empty submit shows a message under each field', (
      tester,
    ) async {
      final harness = routedApp(FakeApi(), initialLocation: Routes.loginPath);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      // Nothing was sent: the form stopped it.
      expect(find.text('Overview'), findsNothing);
    });

    testWidgets('rejects an address that is not an address', (tester) async {
      final harness = routedApp(FakeApi(), initialLocation: Routes.loginPath);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.enterText(_emailField, 'asha@');
      await tester.enterText(_passwordField, 'short');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(find.text('That does not look like an email address.'),
          findsOneWidget);
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
    });

    testWidgets('renders the BankError message and no stack trace', (
      tester,
    ) async {
      final api = FakeApi()
        ..respondError(
          'POST',
          '/auth/login',
          status: 401,
          code: 'AUTH_INVALID_CREDENTIALS',
          message: 'That email or password is not right.',
        );
      final harness = routedApp(api, initialLocation: Routes.loginPath);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await _fillAndSubmit(tester);

      expect(find.text('That email or password is not right.'), findsOneWidget);
      // The banner pairs its colour with an icon.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // Nothing from the exception itself reaches the screen.
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('#0'), findsNothing);
      expect(find.textContaining('AUTH_INVALID_CREDENTIALS'), findsNothing);
      expect(harness.location, Routes.loginPath);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a success lands on Overview without any navigation code', (
      tester,
    ) async {
      final api = FakeApi()..on('POST', '/auth/login', body: testLoginResponse);
      final harness = routedApp(api, initialLocation: Routes.loginPath);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await _fillAndSubmit(tester);

      expect(harness.location, Routes.overviewPath);
      expect(find.text('Signed in as Asha Rao'), findsOneWidget);
      expect(harness.store.stored, testSession);
    });

    testWidgets('signing out returns to sign-in', (tester) async {
      final api = FakeApi()..on('POST', '/auth/login', body: testLoginResponse);
      final harness = routedApp(api, initialLocation: Routes.loginPath);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await _fillAndSubmit(tester);

      await tester.tap(find.byTooltip('Profile and sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(harness.location, Routes.loginPath);
      expect(harness.store.stored, isNull);
    });

    testWidgets('the obscure toggle is labelled both ways', (tester) async {
      final harness = routedApp(FakeApi(), initialLocation: Routes.loginPath);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Show password'), findsOneWidget);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Hide password'), findsOneWidget);
      final field = tester.widget<EditableText>(
        find.descendant(
          of: _passwordField,
          matching: find.byType(EditableText),
        ),
      );
      expect(field.obscureText, isFalse);
    });

    testWidgets('one idempotency key per attempt, reused across a retry', (
      tester,
    ) async {
      final api = FakeApi()
        ..failOnce('POST', '/auth/login')
        ..on('POST', '/auth/login', body: testLoginResponse);
      final harness = routedApp(api, initialLocation: Routes.loginPath);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await _fillAndSubmit(tester);
      expect(find.text('The bank is unavailable.'), findsOneWidget);

      // Same credentials, so the retry must replay the same key rather than
      // risk minting a second session.
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      final keys = api
          .requestsFor('POST', '/auth/login')
          .map((request) => request.idempotencyKey)
          .toList();
      expect(keys, hasLength(2));
      expect(keys.first, isNotNull);
      expect(keys.last, keys.first);
      expect(harness.location, Routes.overviewPath);
    });

    testWidgets('changed credentials start a new attempt with a new key', (
      tester,
    ) async {
      final api = FakeApi()
        ..respondError(
          'POST',
          '/auth/login',
          status: 401,
          code: 'AUTH_INVALID_CREDENTIALS',
          message: 'That email or password is not right.',
          times: 1,
        )
        ..on('POST', '/auth/login', body: testLoginResponse);
      final harness = routedApp(api, initialLocation: Routes.loginPath);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.enterText(_emailField, _email);
      await tester.enterText(_passwordField, 'wrong-password');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      await tester.enterText(_passwordField, _password);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      final keys = api
          .requestsFor('POST', '/auth/login')
          .map((request) => request.idempotencyKey)
          .toList();
      expect(keys, hasLength(2));
      // A different body under the same key is a 409 on the server.
      expect(keys.last, isNot(keys.first));
    });

    testWidgets('does not overflow at textScaler 2.0 on a narrow screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = FakeApi()
        ..respondError(
          'POST',
          '/auth/login',
          status: 401,
          code: 'AUTH_INVALID_CREDENTIALS',
          message: 'That email or password is not right.',
        );
      final harness = routedApp(api, initialLocation: Routes.loginPath);

      await tester.pumpWidget(
        MediaQuery(
          // Built from the real view, so only the text scale changes.
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: harness.app,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The banner is the tallest the screen ever gets; it must still scroll
      // rather than overflow.
      await _fillAndSubmit(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('That email or password is not right.'), findsOneWidget);
    });
  });
}
