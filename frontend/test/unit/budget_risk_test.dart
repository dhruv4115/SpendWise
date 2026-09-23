import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/budgets/data/budget_risk.dart';

/// ₹100.00, so a paisa is a hundredth of a percent of the limit and the
/// thresholds can be walked one paisa at a time.
const int _limit = 10000;

void main() {
  group('riskFor', () {
    test('turns amber at exactly 80% of the limit, and not a paisa before', () {
      // 0.799
      expect(riskFor(spentPaise: 7990, limitPaise: _limit), BudgetRisk.safe);
      expect(riskFor(spentPaise: 7999, limitPaise: _limit), BudgetRisk.safe);
      // 0.8
      expect(riskFor(spentPaise: 8000, limitPaise: _limit), BudgetRisk.warning);
    });

    test('turns red at exactly 100%, not only once it is passed', () {
      // 0.999
      expect(riskFor(spentPaise: 9990, limitPaise: _limit), BudgetRisk.warning);
      expect(riskFor(spentPaise: 9999, limitPaise: _limit), BudgetRisk.warning);
      // 1.0 — the limit is spent, and the next rupee is over it.
      expect(riskFor(spentPaise: 10000, limitPaise: _limit), BudgetRisk.over);
      expect(riskFor(spentPaise: 10001, limitPaise: _limit), BudgetRisk.over);
    });

    test('finds the 80% boundary on a limit that does not divide evenly', () {
      // 80% of 12,345 paise is 9,876 exactly.
      expect(riskFor(spentPaise: 9875, limitPaise: 12345), BudgetRisk.safe);
      expect(riskFor(spentPaise: 9876, limitPaise: 12345), BudgetRisk.warning);
      // Two thirds of a three-paisa limit is nowhere near amber.
      expect(riskFor(spentPaise: 2, limitPaise: 3), BudgetRisk.safe);
      expect(riskFor(spentPaise: 3, limitPaise: 3), BudgetRisk.over);
    });

    test('answers a zero limit instead of dividing by it', () {
      expect(riskFor(spentPaise: 1, limitPaise: 0), BudgetRisk.over);
      expect(riskFor(spentPaise: 500000, limitPaise: 0), BudgetRisk.over);
      // Nothing budgeted and nothing spent is not a problem.
      expect(riskFor(spentPaise: 0, limitPaise: 0), BudgetRisk.safe);
      // Neither is a limit of nothing that has only taken refunds.
      expect(riskFor(spentPaise: -500, limitPaise: 0), BudgetRisk.safe);
    });

    test('a category whose refunds outweigh its spends is on track', () {
      expect(riskFor(spentPaise: -1, limitPaise: _limit), BudgetRisk.safe);
      expect(riskFor(spentPaise: -500000, limitPaise: _limit), BudgetRisk.safe);
      // Exactly nothing spent, on any limit.
      expect(riskFor(spentPaise: 0, limitPaise: _limit), BudgetRisk.safe);
    });
  });

  group('ratioFor', () {
    test('is the used fraction of the limit', () {
      expect(ratioFor(spentPaise: 8000, limitPaise: _limit), 0.8);
      expect(ratioFor(spentPaise: 12000, limitPaise: _limit), 1.2);
      expect(ratioFor(spentPaise: 10000, limitPaise: _limit), 1.0);
    });

    test('is never infinite and never NaN', () {
      // A zero limit that has been spent against is wholly used.
      expect(ratioFor(spentPaise: 1, limitPaise: 0), 1.0);
      expect(ratioFor(spentPaise: 0, limitPaise: 0), 0.0);
      for (final ratio in [
        ratioFor(spentPaise: 1, limitPaise: 0),
        ratioFor(spentPaise: 0, limitPaise: 0),
        ratioFor(spentPaise: -500, limitPaise: 0),
      ]) {
        expect(ratio.isFinite, isTrue);
        expect(ratio.isNaN, isFalse);
      }
    });

    test('a refunded category has used none of its limit', () {
      expect(ratioFor(spentPaise: -500, limitPaise: _limit), 0.0);
    });
  });
}
