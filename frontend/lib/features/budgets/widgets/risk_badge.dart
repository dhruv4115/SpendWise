import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/motion/motion.dart';
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
///
/// A change of state cross-fades over [Motion.riskChange] — the same clock
/// [BudgetRiskBar] moves on, so the words, the icon, the bar's fill and the
/// bar's colour are one event. A badge that snapped to "Over budget" while
/// the bar was still crawling towards it would read as two separate pieces of
/// news about the same budget.
class BudgetRiskBadge extends StatelessWidget {
  const BudgetRiskBadge({super.key, required this.risk});

  final BudgetRisk risk;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motionDuration(context, Motion.riskChange),
      switchInCurve: Motion.standard,
      switchOutCurve: Motion.standard,
      // The pill is sized by the badge arriving, never by the widest of the
      // two: the outgoing one is positioned, so it fades out over the top
      // without widening the row it sits in.
      layoutBuilder: (current, previous) => Stack(
        clipBehavior: Clip.none,
        alignment: AlignmentDirectional.centerStart,
        children: [
          for (final badge in previous)
            Positioned(top: 0, bottom: 0, child: IgnorePointer(child: badge)),
          if (current != null) current,
        ],
      ),
      child: _Pill(key: ValueKey(risk), risk: risk),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.risk});

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
/// Two things move, and they move together: the fill slides to its new
/// fraction while the colour crosses from green to amber to red, both over
/// [Motion.riskChange] and on the same curve. That is the whole point of
/// animating it — a budget that has just tipped over should be seen tipping
/// over, not found already red.
///
/// Both jump to the end state when the platform asks for reduced motion.
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

  static const Duration fillDuration = Motion.riskChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = riskStyleOf(context, risk);
    final target = ratio.clamp(0.0, 1.0);
    // Zero jumps straight to the end state rather than animating there.
    final duration = motionDuration(context, fillDuration);

    return ExcludeSemantics(
      // Nested rather than one controller: two implicit tweens on the same
      // duration and curve stay in step, and neither has to be driven by
      // hand.
      child: TweenAnimationBuilder<Color?>(
        // `begin` is only ever used on the first build, so the bar arrives in
        // its own colour and animates only when the risk actually changes.
        tween: ColorTween(begin: style.color, end: style.color),
        duration: duration,
        curve: Motion.standard,
        builder: (context, colour, _) => TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: target),
          duration: duration,
          curve: Motion.standard,
          builder: (context, value, _) => LinearProgressIndicator(
            value: value,
            minHeight: height,
            borderRadius: BorderRadius.circular(height / 2),
            color: colour ?? style.color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}
