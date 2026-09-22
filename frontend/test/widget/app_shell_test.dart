import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/app.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/widgets/empty_view.dart';
import 'package:spendwise/core/widgets/skeleton.dart';

void main() {
  group('SpendWiseApp', () {
    testWidgets('boots and shows the resolved build configuration', (
      tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: SpendWiseApp()));
      await tester.pumpAndSettle();

      expect(find.text('dev'), findsOneWidget);
      expect(find.text('http://10.0.2.2:3000'), findsOneWidget);
    });

    testWidgets('pairs every risk colour with an icon and a word', (
      tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: SpendWiseApp()));
      await tester.pumpAndSettle();

      expect(find.text('On track'), findsOneWidget);
      expect(find.text('Close to limit'), findsOneWidget);
      expect(find.text('Over budget'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('does not overflow at textScaler 2.0 on a narrow screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ProviderScope(child: SpendWiseApp()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('BudgetRiskTheme.forSpend', () {
    final risk = AppTheme.light().extension<BudgetRiskTheme>()!;

    test('crosses into warning at exactly 80% of the limit', () {
      expect(risk.forSpend(spentPaise: 7999, limitPaise: 10000), risk.safe);
      expect(risk.forSpend(spentPaise: 8000, limitPaise: 10000), risk.warning);
      expect(risk.forSpend(spentPaise: 10000, limitPaise: 10000), risk.warning);
      expect(risk.forSpend(spentPaise: 10001, limitPaise: 10000), risk.over);
    });

    test('treats any spend against a zero limit as over', () {
      expect(risk.forSpend(spentPaise: 1, limitPaise: 0), risk.over);
      expect(risk.forSpend(spentPaise: 0, limitPaise: 0), risk.safe);
    });

    test('a month of net refunds is never a risk', () {
      expect(risk.forSpend(spentPaise: -500, limitPaise: 0), risk.safe);
      expect(risk.forSpend(spentPaise: -500, limitPaise: 10000), risk.safe);
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
