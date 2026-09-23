import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/routes.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/widgets/empty_view.dart';
import 'package:spendwise/core/widgets/skeleton.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_session_store.dart';
import '../helpers/test_app.dart';

void main() {
  group('SpendWiseApp', () {
    testWidgets('boots to sign-in when there is no stored session', (
      tester,
    ) async {
      final harness = routedApp(FakeApi());

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(harness.location, Routes.loginPath);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('boots into the shell when a session is remembered', (
      tester,
    ) async {
      final harness = routedApp(
        FakeApi(),
        store: FakeSessionStore(session: testSession),
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(harness.location, Routes.overviewPath);
      // Four tabs, each labelled: the icon is never the only signal.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Overview'), findsWidgets);
      expect(find.text('Spending'), findsOneWidget);
      expect(find.text('Budgets'), findsOneWidget);
      expect(find.text('Merchants'), findsOneWidget);
    });

    testWidgets('does not overflow at textScaler 2.0 on a narrow screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = routedApp(
        FakeApi(),
        store: FakeSessionStore(session: testSession),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: harness.app,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('BudgetRiskTheme', () {
    // Where the thresholds sit is riskFor's business, and
    // test/unit/budget_risk_test.dart is where they are pinned. What matters
    // here is that the palette gives each of the three states its own icon
    // and its own words, so colour is never carrying the meaning alone.
    test('gives each risk a distinct icon and label', () {
      final risk = AppTheme.riskOf(AppTheme.light());
      final styles = [risk.safe, risk.warning, risk.over];

      expect(styles.map((style) => style.label).toSet(), hasLength(3));
      expect(styles.map((style) => style.icon).toSet(), hasLength(3));
      expect(styles.map((style) => style.color).toSet(), hasLength(3));
    });
  });

  testWidgets('SkeletonList settles when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold(body: SkeletonList(itemCount: 2))),
      ),
    );

    // Would time out here if the pulse kept running.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('EmptyView renders its action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: EmptyView(
            icon: Icons.inbox_outlined,
            title: 'No transactions',
            message: 'Nothing was spent in this month.',
            action: FilledButton(
              onPressed: () {},
              child: const Text('Choose another month'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('No transactions'), findsOneWidget);
    expect(find.text('Nothing was spent in this month.'), findsOneWidget);
    expect(find.text('Choose another month'), findsOneWidget);
  });
}
