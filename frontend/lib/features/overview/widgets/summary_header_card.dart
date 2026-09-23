import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/money.dart';

/// The month's headline: what went out, and how that compares with last
/// month.
///
/// The comparison is never told by colour alone: an arrow and the word
/// "more" or "less" carry it, and the colour only agrees with them.
class SummaryHeaderCard extends StatelessWidget {
  const SummaryHeaderCard({
    super.key,
    required this.monthLabel,
    required this.totalPaise,
    required this.deltaPaise,
    required this.deltaPercent,
  });

  /// `September 2026`.
  final String monthLabel;

  /// Net spend. Negative when refunds outweighed spending.
  final int totalPaise;

  /// This month minus last. Positive means more was spent.
  final int deltaPaise;

  /// [deltaPaise] as a whole percentage of last month, or null when last
  /// month had no spending to compare against.
  final int? deltaPercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final isNetRefund = totalPaise < 0;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        // One announcement for the card: "Spent in September 2026, ₹1,234.00,
        // up ₹200.00 (19%) more than last month."
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isNetRefund
                    ? 'Refunds outweighed spending in $monthLabel'
                    : 'Spent in $monthLabel',
                style: theme.textTheme.titleSmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 4),
              // Scaled down rather than wrapped or cut: an amount is read
              // whole. Proportional figures, since nothing lines up under it.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  formatPaise(totalPaise.abs()),
                  maxLines: 1,
                  style: theme.textTheme.displaySmall
                      ?.copyWith(fontFeatures: const []),
                ),
              ),
              const SizedBox(height: 12),
              _Delta(deltaPaise: deltaPaise, deltaPercent: deltaPercent),
            ],
          ),
        ),
      ),
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta({required this.deltaPaise, required this.deltaPercent});

  final int deltaPaise;
  final int? deltaPercent;

  String get _phrase {
    if (deltaPaise == 0) return 'Same as last month';

    final amount = formatPaise(deltaPaise.abs());
    final percent = switch (deltaPercent?.abs()) {
      null => '',
      // A real change that rounds to nothing still is not "0%".
      0 => ' (under 1%)',
      final whole => ' ($whole%)',
    };
    final direction = deltaPaise > 0 ? 'more' : 'less';
    return '$amount$percent $direction than last month';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final risk = theme.extension<BudgetRiskTheme>();

    // Spending more is the cautionary direction for a spend tracker.
    final (IconData icon, Color colour) = switch (deltaPaise.sign) {
      1 => (Icons.arrow_upward_rounded, scheme.error),
      -1 => (Icons.arrow_downward_rounded, risk?.safe.color ?? scheme.primary),
      _ => (Icons.remove_rounded, scheme.onSurfaceVariant),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Decorative for a screen reader: the words say the direction.
        ExcludeSemantics(
          child: Icon(
            icon,
            size: MediaQuery.textScalerOf(context).scale(20),
            color: colour,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _phrase,
            style: theme.textTheme.bodyLarge?.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}
