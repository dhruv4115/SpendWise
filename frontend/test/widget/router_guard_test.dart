import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/features/transactions/presentation/transaction_screen.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/test_app.dart';

const String _deepLink = '/transactions/abc';
const String _loginWithFrom = '/login?from=%2Ftransactions%2Fabc';

/// The detail screen the deep link points at, whatever it is showing.
final Finder _detailScreen = find.byWidgetPredicate(
  (widget) => widget is TransactionScreen && widget.id == 'abc',
);

Finder get _submit => find.widgetWithText(FilledButton, 'Sign in');

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email address'),
    'asha@example.com',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    'password123',
  );
  await tester.ensureVisible(_submit);
  await tester.pumpAndSettle();
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

void main() {
  group('signed out', () {
    testWidgets('a deep link lands on sign-in, carrying where it was going', (
      tester,
    ) async {
      final harness = routedApp(FakeApi(), initialLocation: _deepLink);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(harness.location, _loginWithFrom);
      expect(find.text('Sign in'), findsOneWidget);
      expect(_detailScreen, findsNothing);
    });

    testWidgets('and after signing in, the deep link opens', (tester) async {
      final api = FakeApi()..on('POST', '/auth/login', body: testLoginResponse);
      final harness = routedApp(api, initialLocation: _deepLink);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      expect(harness.location, _loginWithFrom);

      await _signIn(tester);

      expect(harness.location, _deepLink);
      expect(_detailScreen, findsOneWidget);
      // Inside the shell, not on top of it: the tabs are still there.
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('a bare tab route needs no from parameter', (tester) async {
      final harness = routedApp(
        FakeApi(),
        initialLocation: Routes.overviewPath,
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(harness.location, Routes.loginPath);
    });

    testWidgets('sign-in is reachable on its own terms', (tester) async {
      final harness = routedApp(FakeApi(), initialLocation: Routes.loginPath);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(harness.location, Routes.loginPath);
    });
  });

  group('signed in', () {
    testWidgets('boots through the splash screen to the deep link', (
      tester,
    ) async {
      final harness = routedApp(
        FakeApi(),
        store: FakeSessionStore(session: testSession),
        initialLocation: _deepLink,
      );

      await tester.pumpWidget(harness.app);
      // The first frame is the splash: the keystore has not answered yet, and
      // the destination is being held in the URL while it does.
      expect(find.text('Getting your account ready…'), findsOneWidget);

      await tester.pumpAndSettle();

      expect(harness.location, _deepLink);
      expect(_detailScreen, findsOneWidget);
    });

    testWidgets('cannot sit on the sign-in screen', (tester) async {
      final harness = routedApp(
        FakeApi(),
        store: FakeSessionStore(session: testSession),
        initialLocation: Routes.loginPath,
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(harness.location, Routes.overviewPath);
      expect(find.text('Signed in as Asha Rao'), findsOneWidget);
    });

    testWidgets('each tab keeps its own navigator', (tester) async {
      final harness = routedApp(
        FakeApi(),
        store: FakeSessionStore(session: testSession),
        initialLocation: _deepLink,
      );
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      expect(_detailScreen, findsOneWidget);

      // Away to Budgets…
      await tester.tap(find.text('Budgets'));
      await tester.pumpAndSettle();
      expect(harness.location, Routes.budgetsPath);

      // …and back: the detail page is still where it was left.
      await tester.tap(find.text('Spending'));
      await tester.pumpAndSettle();
      expect(harness.location, _deepLink);
      expect(_detailScreen, findsOneWidget);
    });

    testWidgets('an unknown location gets the not-found screen', (
      tester,
    ) async {
      final harness = routedApp(
        FakeApi(),
        store: FakeSessionStore(session: testSession),
        initialLocation: '/statements/2026',
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text('We could not find that page'), findsOneWidget);
      expect(find.textContaining('unaffected'), findsOneWidget);
      // No exception text, no route dump.
      expect(find.textContaining('GoException'), findsNothing);
    });
  });

  group('the from parameter', () {
    testWidgets('ignores an off-app destination', (tester) async {
      final harness = routedApp(
        FakeApi(),
        store: FakeSessionStore(session: testSession),
        initialLocation: '/login?from=https%3A%2F%2Felsewhere.example',
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(harness.location, Routes.overviewPath);
    });

    testWidgets('ignores one that points back at sign-in', (tester) async {
      final harness = routedApp(
        FakeApi(),
        store: FakeSessionStore(session: testSession),
        initialLocation: '/login?from=%2Flogin',
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(harness.location, Routes.overviewPath);
    });
  });

  group('session expiry', () {
    testWidgets('a 401 anywhere sends the customer back to sign-in', (
      tester,
    ) async {
      final api = FakeApi()
        ..respondError(
          'GET',
          '/transactions',
          status: 401,
          code: 'AUTH_TOKEN_INVALID',
          message: 'Your session has ended.',
        );
      final harness = routedApp(
        api,
        store: FakeSessionStore(session: testSession),
        initialLocation: Routes.transactionsPath,
      );
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      // Nothing here asks for the 401: the feed's own first-page fetch gets
      // it, and the guard does the rest.
      expect(api.requestsFor('GET', '/transactions'), hasLength(1));
      expect(harness.location, '/login?from=%2Ftransactions');
      expect(harness.store.stored, isNull);
    });
  });
}
