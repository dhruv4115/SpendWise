import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/utils/date_format.dart';
import '../../overview/state/summary_provider.dart';
import '../data/budget_repository.dart';
import '../data/budget_risk.dart';
import '../domain/budget.dart';

/// Distinguishes "leave the field alone" from "clear it" in [BudgetView].
const Object _unset = Object();

/// One budget row as a screen needs it: the limit, the spend, and the two
/// derived figures that decide how it is drawn.
///
/// Derived rather than stored — [ratio] and [risk] are computed from the same
/// two integers every time, so a row can never show an amber bar next to an
/// "On track" badge.
@immutable
class BudgetView {
  const BudgetView({
    required this.category,
    required this.limitPaise,
    required this.spentPaise,
    this.rolledOverFrom,
  });

  /// A budget this month has of its own.
  factory BudgetView.of(Budget budget) => BudgetView(
        category: budget.category,
        limitPaise: budget.limitPaise,
        spentPaise: budget.spentPaise,
      );

  final String category;

  /// Never negative: the server rejects that with a 422.
  final int limitPaise;

  /// Spend so far this month, for the whole month — a limit set on the 20th
  /// still counts what went out on the 2nd. Negative in a category whose
  /// refunds outweighed its spends, and not floored here: [risk] and
  /// [remainingPaise] need the real figure.
  final int spentPaise;

  /// The month (`YYYY-MM`) this limit was carried over from, or null when the
  /// customer set it for this month.
  final String? rolledOverFrom;

  /// Whether this row is last month's limit, shown against this month's
  /// spending, waiting to be confirmed by its first edit.
  bool get isRolledOver => rolledOverFrom != null;

  BudgetRisk get risk =>
      riskFor(spentPaise: spentPaise, limitPaise: limitPaise);

  /// For the width of a progress bar. Every decision uses [risk].
  double get ratio => ratioFor(spentPaise: spentPaise, limitPaise: limitPaise);

  /// What is left of the limit. Negative once it is breached.
  int get remainingPaise => limitPaise - spentPaise;

  bool get isOverLimit => risk == BudgetRisk.over;

  /// Spend as it is shown: floored at zero, so a month of refunds reads as
  /// "nothing spent" rather than as a negative. Never used for maths.
  int get displaySpentPaise => spentPaise < 0 ? 0 : spentPaise;

  BudgetView copyWith({
    String? category,
    int? limitPaise,
    int? spentPaise,
    Object? rolledOverFrom = _unset,
  }) {
    return BudgetView(
      category: category ?? this.category,
      limitPaise: limitPaise ?? this.limitPaise,
      spentPaise: spentPaise ?? this.spentPaise,
      rolledOverFrom: identical(rolledOverFrom, _unset)
          ? this.rolledOverFrom
          : rolledOverFrom as String?,
    );
  }

  @override
  String toString() =>
      'BudgetView($category, ${risk.name}, rolledOver: $isRolledOver)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BudgetView &&
          other.category == category &&
          other.limitPaise == limitPaise &&
          other.spentPaise == spentPaise &&
          other.rolledOverFrom == rolledOverFrom;

  @override
  int get hashCode =>
      Object.hash(category, limitPaise, spentPaise, rolledOverFrom);
}

extension BudgetViewLookup on List<BudgetView> {
  /// The row for [category], or null when nothing is budgeted for it.
  BudgetView? forCategory(String category) {
    for (final budget in this) {
      if (budget.category == category) return budget;
    }
    return null;
  }
}

/// One month's budgets, keyed by `YYYY-MM`.
///
/// Each row carries its category's spend, so a recategorisation invalidates
/// this for the months it touched.
///
/// A month the customer has not budgeted yet is not empty: budgets roll over,
/// so last month's limits are shown against this month's spending until the
/// first edit makes them this month's own. See [_carriedOver].
class BudgetsNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<BudgetView>, String> {
  @override
  Future<List<BudgetView>> build(String month) async {
    final repository = ref.watch(budgetRepositoryProvider);

    final budgets = await repository.fetchBudgets(month);
    if (budgets.isNotEmpty) {
      return List.unmodifiable([
        for (final budget in budgets) BudgetView.of(budget),
      ]);
    }
    return _carriedOver(month, repository);
  }

  /// Last month's limits against this month's spending.
  ///
  /// A customer who budgeted ₹5,000 for food in August has not stopped
  /// budgeting for food in September, and should not arrive on the 1st to an
  /// empty screen. The rows are marked [BudgetView.isRolledOver] so the UI can
  /// say where they came from, and saving one is what writes it to this month.
  ///
  /// The spend cannot come from the budget rows — there are none — so it comes
  /// from the month's summary, which counts the whole month however late in it
  /// the limit is finally confirmed.
  Future<List<BudgetView>> _carriedOver(
    String month,
    BudgetRepository repository,
  ) async {
    final previousMonth = addMonths(month, -1);
    final previous = await repository.fetchBudgets(previousMonth);
    if (previous.isEmpty) return const [];

    final summary = await ref.watch(summaryProvider(month).future);
    return List.unmodifiable([
      for (final budget in previous)
        BudgetView(
          category: budget.category,
          limitPaise: budget.limitPaise,
          spentPaise: summary.byCategory[budget.category] ?? 0,
          rolledOverFrom: previousMonth,
        ),
    ]);
  }

  /// Fetches again, keeping the current rows on screen until the new ones
  /// land. Never throws — a failure is in [state] — so pull-to-refresh and a
  /// Retry button can both call it.
  ///
  /// The month's summary goes too: a carried-over month takes its spending
  /// from there, and a refresh that left it cached would redraw the same
  /// numbers.
  Future<void> refresh() async {
    ref.invalidate(summaryProvider(arg));
    ref.invalidateSelf();
    try {
      await future;
    } on BankError {
      // Already in state as an AsyncError; the screen renders it.
    }
  }
}

final AutoDisposeAsyncNotifierProviderFamily<BudgetsNotifier, List<BudgetView>,
        String> budgetsProvider =
    AsyncNotifierProvider.autoDispose
        .family<BudgetsNotifier, List<BudgetView>, String>(
  BudgetsNotifier.new,
);

/// One budget's coordinates: which category, in which month.
///
/// The family key for the edit screen's providers, so two screens on the same
/// budget share one draft and one idempotency key, and the same category in
/// another month is a different budget.
@immutable
class BudgetTarget {
  const BudgetTarget({required this.month, required this.category});

  /// `YYYY-MM`.
  final String month;
  final String category;

  BudgetTarget copyWith({String? month, String? category}) {
    return BudgetTarget(
      month: month ?? this.month,
      category: category ?? this.category,
    );
  }

  @override
  String toString() => 'BudgetTarget($month, $category)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BudgetTarget &&
          other.month == month &&
          other.category == category;

  @override
  int get hashCode => Object.hash(month, category);
}

/// The row the edit screen starts from.
///
/// Usually the month's own budget for that category, carried-over flag and
/// all. For a category with no budget yet it is a blank limit seeded with
/// what has already gone out of that category this month — the whole month,
/// which is what makes the live preview tell the truth on the 20th.
final AutoDisposeFutureProviderFamily<BudgetView, BudgetTarget>
    budgetDraftProvider =
    FutureProvider.autoDispose.family<BudgetView, BudgetTarget>(
  (ref, target) async {
    final budgets = await ref.watch(budgetsProvider(target.month).future);
    final existing = budgets.forCategory(target.category);
    if (existing != null) return existing;

    final summary = await ref.watch(summaryProvider(target.month).future);
    return BudgetView(
      category: target.category,
      limitPaise: 0,
      spentPaise: summary.byCategory[target.category] ?? 0,
    );
  },
);
