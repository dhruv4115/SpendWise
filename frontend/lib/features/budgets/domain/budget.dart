import 'package:flutter/foundation.dart';

import '../../../core/utils/json_read.dart';

/// A spending limit for one category in one month, and how much of it is gone.
///
/// Both figures are "spend" amounts — already sign-flipped by the server — so
/// they are positive when money has left the account. A month whose refunds
/// outweigh its spends has a negative [spentPaise], which is not a bug and
/// must not be floored anywhere except at the moment of display.
@immutable
class Budget {
  const Budget({
    required this.category,
    required this.month,
    required this.limitPaise,
    required this.spentPaise,
  });

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      category: readString(json, 'category'),
      month: readString(json, 'month'),
      limitPaise: readInt(json, 'limitPaise'),
      // A budget that has just been created comes back without a spend.
      spentPaise: readIntOr(json, 'spentPaise', 0),
    );
  }

  final String category;

  /// `YYYY-MM`.
  final String month;

  /// The ceiling the customer set. Never negative — the server rejects that
  /// with a 422.
  final int limitPaise;

  /// Spent so far this month in this category.
  final int spentPaise;

  /// What is left. Negative once the limit is breached.
  int get remainingPaise => limitPaise - spentPaise;

  bool get isOverLimit => spentPaise > limitPaise;

  /// Progress against the limit, 0–100+, using integer maths only.
  /// A zero or unset limit reads as 0 so a progress bar has something sane to
  /// draw; [isOverLimit] is what decides the warning.
  int get usedPercent {
    if (limitPaise <= 0) return 0;
    if (spentPaise <= 0) return 0;
    return spentPaise * 100 ~/ limitPaise;
  }

  Budget copyWith({
    String? category,
    String? month,
    int? limitPaise,
    int? spentPaise,
  }) {
    return Budget(
      category: category ?? this.category,
      month: month ?? this.month,
      limitPaise: limitPaise ?? this.limitPaise,
      spentPaise: spentPaise ?? this.spentPaise,
    );
  }

  @override
  String toString() => 'Budget($category, $month)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Budget &&
          other.category == category &&
          other.month == month &&
          other.limitPaise == limitPaise &&
          other.spentPaise == spentPaise;

  @override
  int get hashCode => Object.hash(category, month, limitPaise, spentPaise);
}
