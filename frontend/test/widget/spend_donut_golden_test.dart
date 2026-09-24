import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/overview/domain/overview_data.dart';
import 'package:spendwise/features/overview/widgets/spend_donut.dart';

/// A fixed month: six named categories and a fold. Built by hand rather than
/// derived, so the golden only changes when the widget does.
const List<CategorySlice> _slices = [
  CategorySlice(
    category: 'food',
    label: 'Food & Dining',
    paise: 450000,
    sharePercent: 41,
    argb: 0xFFE8590C,
  ),
  CategorySlice(
    category: 'groceries',
    label: 'Groceries',
    paise: 300000,
    sharePercent: 28,
    argb: 0xFF2F9E44,
  ),
  CategorySlice(
    category: 'transport',
    label: 'Transport',
    paise: 120000,
    sharePercent: 11,
    argb: 0xFF1C7ED6,
  ),
  CategorySlice(
    category: 'shopping',
    label: 'Shopping',
    paise: 90000,
    sharePercent: 8,
    argb: 0xFF9C36B5,
  ),
  CategorySlice(
    category: 'bills',
    label: 'Bills & Utilities',
    paise: 60000,
    sharePercent: 5,
    argb: 0xFFF08C00,
  ),
  CategorySlice(
    category: 'entertainment',
    label: 'Entertainment',
    paise: 30000,
    sharePercent: 3,
    argb: 0xFFD6336C,
  ),
  CategorySlice(label: 'Other', paise: 40000, sharePercent: 4),
];

final Key _boundary = UniqueKey();

Future<void> _pumpDonut(
  WidgetTester tester,
  ThemeData theme, {
  List<CategorySlice> slices = _slices,
  bool reducedMotion = true,
}) async {
  tester.view.physicalSize = const Size(400, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Reduced motion, the way the platform reports it.
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reducedMotion);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: _boundary,
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 360,
                  child: SpendDonut(
                    month: '2026-09',
                    slices: slices,
                    onSliceTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // One frame is the whole story: with reduced motion nothing is animating.
  await tester.pump();
}

void main() {
  testWidgets('with reduced motion a change of data jumps, not animates', (
    tester,
  ) async {
    await _pumpDonut(tester, AppTheme.light());
    final context = tester.element(find.byType(SpendDonut));
    expect(MediaQuery.of(context).disableAnimations, isTrue);

    // Next month's numbers: every slice changes size.
    await _pumpDonut(
      tester,
      AppTheme.light(),
      slices: [for (final slice in _slices.reversed) slice],
    );

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('without it, the same change animates', (tester) async {
    await _pumpDonut(tester, AppTheme.light(), reducedMotion: false);
    await _pumpDonut(
      tester,
      AppTheme.light(),
      reducedMotion: false,
      slices: [for (final slice in _slices.reversed) slice],
    );

    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('SpendDonut, light', (tester) async {
    await _pumpDonut(tester, AppTheme.light());

    await expectLater(
      find.byKey(_boundary),
      matchesGoldenFile('goldens/spend_donut_light.png'),
    );
  });

  testWidgets('SpendDonut, dark', (tester) async {
    await _pumpDonut(tester, AppTheme.dark());

    await expectLater(
      find.byKey(_boundary),
      matchesGoldenFile('goldens/spend_donut_dark.png'),
    );
  });
}
