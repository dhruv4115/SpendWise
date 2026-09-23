import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';
import '../domain/transaction.dart';

/// Widest the amount may render before it is scaled down to fit.
const double _amountMaxWidth = 168;

/// One row of the feed: category icon, merchant, payment mode and the signed
/// amount.
///
/// Every tile is the same height by construction — one line of merchant, one
/// line of chips, and strut heights forced on both, so a glyph from a fallback
/// font cannot make one row taller than the rest. That lets the list measure a
/// single [prototype] instead of laying out every row. The prototype is a real
/// tile laid out under the real text scale, so the shared height grows with
/// the customer's font size instead of clipping it.
///
/// A refund is never told apart by colour alone: it carries a `+`, an undo
/// icon and the word "Refund".
class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction, this.onTap});

  final Transaction transaction;
  final VoidCallback? onTap;

  /// What [prototype] shows. It is laid out but never painted, hit-tested or
  /// announced, so the content only has to be the right shape.
  static final Transaction prototypeTransaction = Transaction(
    id: 'prototype',
    merchantRaw: 'PROTOTYPE',
    merchantName: 'Prototype',
    merchantKey: 'prototype',
    category: 'other',
    amountPaise: -100,
    at: DateTime(2000),
    mode: 'UPI',
  );

  /// The row a list measures to learn every row's height.
  static final TransactionTile prototype =
      TransactionTile(transaction: prototypeTransaction);

  String get _semanticLabel {
    final amount = formatPaise(transaction.amountPaise.abs());
    final money = transaction.isRefund ? 'Refund of $amount' : 'Spent $amount';
    return '${transaction.merchantName}. $money. '
        '${modeLabel(transaction.mode)}.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRefund = transaction.isRefund;

    final titleStyle = theme.textTheme.bodyLarge!;
    final titleStrut = StrutStyle.fromTextStyle(
      titleStyle,
      forceStrutHeight: true,
    );
    final amountStyle = titleStyle.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: isRefund ? scheme.primary : scheme.onSurface,
    );

    // One node for the whole row, read as a sentence, rather than five
    // fragments a screen reader has to stitch together.
    return Semantics(
      button: onTap != null,
      onTap: onTap,
      label: _semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _CategoryAvatar(category: transaction.category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            transaction.merchantName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                            strutStyle: titleStrut,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Scaled down rather than cut off: an ellipsis inside
                        // an amount would misstate it.
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _amountMaxWidth,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              formatSignedPaise(transaction.amountPaise),
                              maxLines: 1,
                              softWrap: false,
                              style: amountStyle,
                              strutStyle: titleStrut,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Both variants of this line are chips of one height, so
                    // a refund row is exactly as tall as a spend row.
                    Row(
                      children: [
                        if (isRefund) ...[
                          Flexible(
                            child: _TileChip(
                              icon: Icons.undo_rounded,
                              label: 'Refund',
                              background: scheme.primaryContainer,
                              foreground: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: _TileChip(
                            label: modeLabel(transaction.mode),
                            background: scheme.surfaceContainerHighest,
                            foreground: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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

class _CategoryAvatar extends StatelessWidget {
  const _CategoryAvatar({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          categoryIcon(category),
          size: 20,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _TileChip extends StatelessWidget {
  const _TileChip({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style =
        Theme.of(context).textTheme.labelSmall!.copyWith(color: foreground);
    final chipIcon = icon;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chipIcon != null) ...[
              // Grows with the text, and stays shorter than its line.
              Icon(
                chipIcon,
                size: MediaQuery.textScalerOf(context).scale(12),
                color: foreground,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
                strutStyle: StrutStyle.fromTextStyle(
                  style,
                  forceStrutHeight: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The icon for a category id. Mirrors the icon names `GET /categories` sends
/// for the seeded categories; one the app has not heard of gets a generic
/// icon rather than a crash.
IconData categoryIcon(String category) => switch (category) {
      'food' => Icons.restaurant,
      'groceries' => Icons.shopping_basket,
      'transport' => Icons.directions_bus,
      'shopping' => Icons.shopping_bag,
      'bills' => Icons.receipt_long,
      'entertainment' => Icons.movie,
      'health' => Icons.medical_services,
      'travel' => Icons.flight,
      'education' => Icons.school,
      _ => Icons.category,
    };

/// A payment rail as a customer would say it. An unknown one is shown as the
/// server sent it rather than hidden.
String modeLabel(String mode) => switch (mode) {
      'UPI' => 'UPI',
      'CARD' => 'Card',
      'NETBANKING' => 'Net banking',
      'CASH' => 'Cash',
      'AUTOPAY' => 'Autopay',
      _ => mode,
    };
