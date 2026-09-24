import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/motion/motion.dart';
import 'package:spendwise/features/budgets/data/budget_risk.dart';
import 'package:spendwise/features/budgets/widgets/risk_badge.dart';
import 'package:spendwise/features/overview/domain/overview_data.dart';
import 'package:spendwise/features/overview/widgets/spend_donut.dart';

const List<CategorySlice> _september = [
  CategorySlice(
    category: 'food',
    label: 'Food & Dining',
    paise: 600000,
    sharePercent: 60,
    argb: 0xFFE8590C,
  ),
  CategorySlice(
    category: 'transport',
    label: 'Transport',
    paise: 400000,
    sharePercent: 40,
    argb: 0xFF1C7ED6,
  ),
];

/// The same month, recategorised: one slice bigger, one smaller.
const List<CategorySlice> _recategorised = [
  CategorySlice(
    category: 'food',
    label: 'Food & Dining',
    paise: 700000,
    sharePercent: 70,
    argb: 0xFFE8590C,
  ),
  CategorySlice(
    category: 'transport',
    label: 'Transport',
    paise: 300000,
    sharePercent: 30,
    argb: 0xFF1C7ED6,
  ),
];

Widget _app(Widget child, {bool reducedMotion = false}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child:
            Scaffold(body: Center(child: SizedBox(width: 360, child: child))),
      ),
    ),
  );
}

/// How much of a full turn the ring is currently drawing: the visible
/// sections over everything the chart is holding open, transparent tail
/// included.
double _drawnFraction(WidgetTester tester) {
  final sections = tester.widget<PieChart>(find.byType(PieChart)).data.sections;
  var drawn = 0.0;
  var total = 0.0;
  for (final section in sections) {
    total += section.value;
    if (section.color != Colors.transparent) drawn += section.value;
  }
  return total == 0 ? 0 : drawn / total;
}

Color? _barColour(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
    .color;

double? _barValue(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
    .value;

void main() {
  group('the donut sweeps in on the first paint of a month', () {
    testWidgets('from nothing to the whole ring, over 450 ms', (tester) async {
      await tester.pumpWidget(
        _app(const SpendDonut(month: '2026-09', slices: _september)),
      );

      // First frame: nothing of the ring is drawn yet.
      expect(_drawnFraction(tester), closeTo(0, 0.001));

      await tester.pump(const Duration(milliseconds: 225));
      final halfway = _drawnFraction(tester);
      expect(halfway, greaterThan(0));
      expect(halfway, lessThan(1));

      await tester.pump(Motion.donutSweep);
      expect(_drawnFraction(tester), closeTo(1, 0.001));
      // And nothing is left animating.
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('but lands whole in the first frame under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SpendDonut(month: '2026-09', slices: _september),
          reducedMotion: true,
        ),
      );

      expect(_drawnFraction(tester), closeTo(1, 0.001));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('a change of figures cross-fades', () {
    testWidgets('rather than sweeping the new ring in again', (tester) async {
      await tester.pumpWidget(
        _app(const SpendDonut(month: '2026-09', slices: _september)),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(const SpendDonut(month: '2026-09', slices: _recategorised)),
      );
      await tester.pump();

      // Two rings on screen, one fading out over the other…
      expect(find.byType(PieChart), findsNWidgets(2));
      // …and the arriving one is whole from its first frame: the figures
      // changed, the month did not.
      for (final chart in tester.widgetList<PieChart>(find.byType(PieChart))) {
        final values = [for (final s in chart.data.sections) s.value];
        expect(values.any((value) => value == 0), isFalse);
        expect(
          chart.data.sections.any((s) => s.color == Colors.transparent),
          isFalse,
        );
      }

      await tester.pumpAndSettle();
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('and a new month sweeps, because it is a new chart', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const SpendDonut(month: '2026-09', slices: _september)),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(const SpendDonut(month: '2026-08', slices: _recategorised)),
      );
      await tester.pump();

      final arriving = tester.widgetList<PieChart>(find.byType(PieChart)).last;
      expect(
        arriving.data.sections.any((s) => s.color == Colors.transparent),
        isTrue,
        reason: 'the new month should be drawing itself in',
      );

      await tester.pumpAndSettle();
      expect(_drawnFraction(tester), closeTo(1, 0.001));
    });
  });

  group('the budget bar moves with its badge', () {
    testWidgets('fill and colour cross together over 300 ms', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              BudgetRiskBar(ratio: 0.5, risk: BudgetRisk.safe),
              BudgetRiskBadge(risk: BudgetRisk.safe),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final safeColour = _barColour(tester);
      expect(find.text('On track'), findsOneWidget);

      // The customer spends past the limit.
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              BudgetRiskBar(ratio: 1.2, risk: BudgetRisk.over),
              BudgetRiskBadge(risk: BudgetRisk.over),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      // Halfway: the bar is between the two fills and between the two
      // colours, and both badges are on screen mid-fade — one event, not
      // three.
      expect(_barValue(tester), greaterThan(0.5));
      expect(_barValue(tester), lessThan(1.0));
      final middle = _barColour(tester);
      expect(middle, isNot(safeColour));
      expect(find.text('On track'), findsOneWidget);
      expect(find.text('Over budget'), findsOneWidget);

      await tester.pump(Motion.riskChange);
      expect(_barValue(tester), 1.0);
      expect(_barColour(tester), isNot(middle));
      expect(find.text('On track'), findsNothing);
      expect(find.text('Over budget'), findsOneWidget);
    });

    testWidgets('and land on the end state at once under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              BudgetRiskBar(ratio: 0.5, risk: BudgetRisk.safe),
              BudgetRiskBadge(risk: BudgetRisk.safe),
            ],
          ),
          reducedMotion: true,
        ),
      );
      await tester.pump();
      final safeColour = _barColour(tester);

      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              BudgetRiskBar(ratio: 1.2, risk: BudgetRisk.over),
              BudgetRiskBadge(risk: BudgetRisk.over),
            ],
          ),
          reducedMotion: true,
        ),
      );
      await tester.pump();

      expect(_barValue(tester), 1.0);
      expect(_barColour(tester), isNot(safeColour));
      expect(find.text('Over budget'), findsOneWidget);
      expect(find.text('On track'), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
