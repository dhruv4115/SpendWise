import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';
import '../domain/overview_data.dart';

/// Spending by category as a ring, with a legend that names every slice.
///
/// Colour follows the category, never its rank, so Food is the same colour
/// in every month. The legend is the dependable identity channel — some
/// category colours sit close together — and a 2 px gap separates every
/// slice. Text is never drawn in a slice's colour; a swatch beside it
/// carries the match.
///
/// Takes plain data and no providers, so it can be golden-tested.
class SpendDonut extends StatelessWidget {
  const SpendDonut({super.key, required this.slices, this.onSliceTap});

  /// Largest first, drawn clockwise from twelve o'clock.
  final List<CategorySlice> slices;

  /// Called with a slice that stands for one category. A fold has no single
  /// feed to open, so it is not tappable.
  final ValueChanged<CategorySlice>? onSliceTap;

  static const double holeRadius = 52;
  static const double ringWidth = 36;
  static const double diameter = 2 * (holeRadius + ringWidth);

  static const Duration _animation = Duration(milliseconds: 300);

  /// The fold wears the theme's neutral: it is "everything else", not an
  /// identity.
  static Color colourOf(CategorySlice slice, ColorScheme scheme) {
    final argb = slice.argb;
    return argb == null ? scheme.outline : Color(argb);
  }

  void _onTouch(FlTouchEvent event, PieTouchResponse? response) {
    final onTap = onSliceTap;
    if (onTap == null || event is! FlTapUpEvent) return;

    final index = response?.touchedSection?.touchedSectionIndex ?? -1;
    if (index < 0 || index >= slices.length) return;
    final slice = slices[index];
    if (!slice.isFold) onTap(slice);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final animate = !MediaQuery.of(context).disableAnimations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The ring is announced once, as what it is; the legend below reads
        // out every slice with its amount and share.
        Semantics(
          label: 'Donut chart of spending by category. '
              'Each category is listed below it.',
          excludeSemantics: true,
          child: RepaintBoundary(
            child: SizedBox(
              height: diameter,
              child: PieChart(
                PieChartData(
                  sections: [
                    for (final slice in slices)
                      PieChartSectionData(
                        value: slice.paise.toDouble(),
                        color: colourOf(slice, scheme),
                        radius: ringWidth,
                        showTitle: false,
                      ),
                  ],
                  centerSpaceRadius: holeRadius,
                  sectionsSpace: 2,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    enabled: onSliceTap != null,
                    touchCallback: _onTouch,
                  ),
                ),
                // Reduced motion lands on the final ring at once.
                duration: animate ? _animation : Duration.zero,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final slice in slices)
          _LegendRow(
            slice: slice,
            colour: colourOf(slice, scheme),
            onTap: slice.isFold || onSliceTap == null
                ? null
                : () => onSliceTap!(slice),
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slice, required this.colour, this.onTap});

  final CategorySlice slice;
  final Color colour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final amount = formatPaise(slice.paise);

    return Semantics(
      button: onTap != null,
      label: '${slice.label}, $amount, ${slice.sharePercent} percent',
      hint: onTap == null ? null : 'Shows these transactions',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: SizedBox.square(
                  dimension: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colour,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slice.label, style: theme.textTheme.bodyLarge),
                    Text(
                      '$amount · ${slice.sharePercent}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
