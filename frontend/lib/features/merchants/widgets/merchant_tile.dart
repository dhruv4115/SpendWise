import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';
import '../../transactions/widgets/transaction_tile.dart';
import '../domain/merchant_insight.dart';

/// One merchant in the list: what they took this month, how often, and what
/// that averages out at.
///
/// All three figures are on screen at once whatever the list is sorted by —
/// re-ordering a list is a weak signal on its own, and a customer should not
/// have to change the sort to find out how many times they went.
class MerchantTile extends StatelessWidget {
  const MerchantTile({
    super.key,
    required this.insight,
    required this.categoryName,
    this.onTap,
  });

  final MerchantInsight insight;

  /// The name of [MerchantInsight.topCategory], as the server calls it.
  final String categoryName;

  final VoidCallback? onTap;

  /// Read as one sentence rather than five fragments.
  String get _semanticLabel =>
      '${insight.merchantName}. ${formatPaise(insight.totalPaise)} over '
      '${_visitsLabel(insight.visits)}, '
      '${formatPaise(insight.avgPaise)} on average. $categoryName.';

  static String _visitsLabel(int visits) =>
      visits == 1 ? '1 payment' : '$visits payments';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final amountStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Semantics(
      button: onTap != null,
      onTap: onTap,
      label: _semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    categoryIcon(insight.topCategory),
                    size: 20,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.merchantName,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(categoryName, style: muted),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Wraps under the name rather than squeezing it at a 2.0 text
              // scale: an amount is scaled down, never cut off.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 176),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        formatPaise(insight.totalPaise),
                        maxLines: 1,
                        softWrap: false,
                        style: amountStyle,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        '${_visitsLabel(insight.visits)} · '
                        '${formatPaise(insight.avgPaise)} avg',
                        maxLines: 1,
                        softWrap: false,
                        style: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
