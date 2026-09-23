import 'package:flutter/material.dart';

import '../../../core/utils/date_format.dart';
import '../../../core/utils/money.dart';
import '../../transactions/widgets/transaction_tile.dart' show categoryIcon;
import '../state/budgets_provider.dart';
import 'risk_badge.dart';

/// One budget on the list: what it is for, how much of it is gone, and
/// whether that is a problem.
///
/// Read as a single sentence by a screen reader — five fragments stitched
/// together is not how anyone would say it — and the sentence carries the
/// risk in words, so nothing is lost when the colour is.
class BudgetCard extends StatelessWidget {
  const BudgetCard({
    super.key,
    required this.budget,
    required this.categoryName,
    this.onTap,
  });

  final BudgetView budget;

  /// The server's name for the category, resolved by the screen: this card
  /// does not fetch.
  final String categoryName;

  final VoidCallback? onTap;

  /// "₹4,200.00 of ₹5,000.00".
  String get _amounts => '${formatPaise(budget.displaySpentPaise)} of '
      '${formatPaise(budget.limitPaise)}';

  /// What is left, or by how much the limit is gone.
  String get _balance => budget.isOverLimit
      ? '${formatPaise(budget.remainingPaise.abs())} over'
      : '${formatPaise(budget.remainingPaise)} left';

  String? get _carriedOver => budget.rolledOverFrom == null
      ? null
      : 'Carried over from ${monthKeyLabel(budget.rolledOverFrom!)}';

  String _semanticLabel(BuildContext context) {
    final carried = _carriedOver;
    return '$categoryName. ${riskStyleOf(context, budget.risk).label}. '
        '$_amounts spent. $_balance.${carried == null ? '' : ' $carried.'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final carried = _carriedOver;

    return Card(
      margin: EdgeInsets.zero,
      child: Semantics(
        button: onTap != null,
        onTap: onTap,
        label: _semanticLabel(context),
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox.square(
                      dimension: 40,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          categoryIcon(budget.category),
                          size: 20,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        categoryName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                BudgetRiskBar(ratio: budget.ratio, risk: budget.risk),
                const SizedBox(height: 12),
                // Wraps rather than squeezes: at a 2.0 text scale the badge
                // and the amounts each take their own line.
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    BudgetRiskBadge(risk: budget.risk),
                    Text(_amounts, style: theme.textTheme.bodyMedium),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_balance, style: muted),
                if (carried != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: MediaQuery.textScalerOf(context).scale(16),
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(carried, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
