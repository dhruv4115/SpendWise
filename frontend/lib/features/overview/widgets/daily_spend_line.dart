import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/date_format.dart';
import '../../../core/utils/money.dart';
import '../domain/month_summary.dart';

/// Spending on each day of the month, as one line.
///
/// A single series, so no legend: the section title names it. Straight
/// segments rather than a smoothed curve — a curve overshoots between days
/// and draws spending that never happened. Hairline, solid horizontal grid;
/// a 10% wash under the line down to zero.
///
/// Takes plain data and no providers, so it can be golden-tested.
class DailySpendLine extends StatefulWidget {
  const DailySpendLine({super.key, required this.days});

  /// Every day of the month, ascending, zero-filled.
  final List<DailyTotal> days;

  static const double plotHeight = 180;

  @override
  State<DailySpendLine> createState() => _DailySpendLineState();
}

class _DailySpendLineState extends State<DailySpendLine> {
  static const Duration _animation = Duration(milliseconds: 300);

  /// Worked out when the days change, not on every build.
  late _Geometry _geometry = _Geometry.of(widget.days);

  @override
  void didUpdateWidget(DailySpendLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.days, widget.days)) {
      _geometry = _Geometry.of(widget.days);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    if (days.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final animate = !MediaQuery.of(context).disableAnimations;
    final geometry = _geometry;

    final axisStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final leftReserved = scaler.scale(48);
    final bottomReserved = scaler.scale(24);

    return Semantics(
      label: geometry.summary,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: SizedBox(
          // The axis labels are inside this height, so a larger text size
          // grows the chart instead of clipping the day numbers.
          height: DailySpendLine.plotHeight + bottomReserved,
          child: LineChart(
            LineChartData(
              minX: 1,
              maxX: days.length.toDouble(),
              minY: geometry.bottom.toDouble(),
              maxY: geometry.top.toDouble(),
              lineBarsData: [
                LineChartBarData(
                  spots: geometry.spots,
                  color: scheme.primary,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  isStrokeJoinRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: scheme.primary.withValues(alpha: 0.1),
                    applyCutOffY: true,
                  ),
                ),
              ],
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: geometry.step.toDouble(),
                getDrawingHorizontalLine: (_) => FlLine(
                  color: scheme.outlineVariant,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: geometry.step.toDouble(),
                    reservedSize: leftReserved,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(abbreviate(value.round()), style: axisStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 7,
                    reservedSize: bottomReserved,
                    // The last day would crowd the last weekly tick.
                    maxIncluded: false,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text('${value.round()}', style: axisStyle),
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipColor: (_) => scheme.inverseSurface,
                  getTooltipItems: (touched) => [
                    for (final spot in touched)
                      LineTooltipItem(
                        '${shortDateLabel(days[spot.x.round() - 1].date)}\n'
                        '${formatPaise(spot.y.round())}',
                        theme.textTheme.bodySmall!.copyWith(
                          color: scheme.onInverseSurface,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            duration: animate ? _animation : Duration.zero,
          ),
        ),
      ),
    );
  }
}

/// The plotted points and an axis that starts at zero and steps in round
/// amounts: 1, 2 or 5 times a power of ten, in paise.
class _Geometry {
  _Geometry({
    required this.spots,
    required this.bottom,
    required this.top,
    required this.step,
    required this.summary,
  });

  factory _Geometry.of(List<DailyTotal> days) {
    var highest = 0;
    var lowest = 0;
    DailyTotal? busiest;
    for (final day in days) {
      highest = math.max(highest, day.paise);
      lowest = math.min(lowest, day.paise);
      if (day.paise > 0 && (busiest == null || day.paise > busiest.paise)) {
        busiest = day;
      }
    }

    // A month of zeros still needs an axis with some height to it.
    final step = _roundStep(math.max(highest - lowest, 300) ~/ 3);
    final top = _ceilTo(highest, step);
    final bottom = -_ceilTo(-lowest, step);

    return _Geometry(
      spots: [
        for (final day in days)
          FlSpot(day.date.day.toDouble(), day.paise.toDouble()),
      ],
      bottom: bottom,
      top: top > bottom ? top : bottom + step,
      step: step,
      summary: busiest == null
          ? 'Line chart of spending each day. No day had any spending.'
          : 'Line chart of spending each day. The busiest day was '
              '${shortDateLabel(busiest.date)}, at '
              '${formatPaise(busiest.paise)}.',
    );
  }

  final List<FlSpot> spots;
  final int bottom;
  final int top;
  final int step;
  final String summary;

  /// The smallest 1, 2 or 5 × 10ⁿ that is at least [rough].
  static int _roundStep(int rough) {
    var magnitude = 1;
    while (magnitude * 10 <= rough) {
      magnitude *= 10;
    }
    for (final multiple in const [1, 2, 5, 10]) {
      if (magnitude * multiple >= rough) return magnitude * multiple;
    }
    return magnitude * 10;
  }

  static int _ceilTo(int value, int step) =>
      value <= 0 ? 0 : (value + step - 1) ~/ step * step;
}
