import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../data/budget_risk.dart';

/// The palette the active theme paints [risk] in.
///
/// The only place a [BudgetRisk] becomes a colour, so the thresholds stay in
/// `data/` — where they are integer maths and unit-tested — and the palette
/// stays in the theme.
RiskStyle riskStyleOf(BuildContext context, BudgetRisk risk) {
  final palette = AppTheme.riskOf(Theme.of(context));
  return switch (risk) {
    BudgetRisk.safe => palette.safe,
    BudgetRisk.warning => palette.warning,
    BudgetRisk.over => palette.over,
  };
}

/// "On track", "Nearing limit" or "Over budget", as a tinted pill with the
/// matching icon.
///
/// The colour is the third signal, never the first: the words say the state,
/// the icon repeats it, and either alone is enough to read the badge in
/// greyscale or with any kind of colour blindness.
class BudgetRiskBadge extends StatelessWidget {
  const BudgetRiskBadge({super.key, required this.risk});

  final BudgetRisk risk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = riskStyleOf(context, risk);
    final textStyle = theme.textTheme.labelMedium?.copyWith(
      color: style.onContainerColor,
      fontWeight: FontWeight.w600,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.containerColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grows with the customer's text size, so the pill never ends up
            // with a tiny glyph beside large words.
            Icon(
              style.icon,
              size: MediaQuery.textScalerOf(context).scale(16),
              color: style.onContainerColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                style.label,
                style: textStyle,
                strutStyle: textStyle == null
                    ? null
                    : StrutStyle.fromTextStyle(textStyle,
                        forceStrutHeight: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How much of a limit is gone, as a bar.
///
/// Animates to its value once, and sits at it from the start when the
/// platform asks for reduced motion.
class BudgetRiskBar extends StatelessWidget {
  const BudgetRiskBar({
    super.key,
    required this.ratio,
    required this.risk,
    this.height = 10,
  });

  /// Used fraction of the limit. Over 1 is clamped: a bar cannot be more than
  /// full, and the badge is what says by how much.
  final double ratio;
  final BudgetRisk risk;
  final double height;

  static const Duration fillDuration = Duration(milliseconds: 600);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = riskStyleOf(context, risk);
    final target = ratio.clamp(0.0, 1.0);

    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        // Zero jumps straight to the end state rather than animating there.
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : fillDuration,
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => LinearProgressIndicator(
          value: value,
          minHeight: height,
          borderRadius: BorderRadius.circular(height / 2),
          color: style.color,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}
