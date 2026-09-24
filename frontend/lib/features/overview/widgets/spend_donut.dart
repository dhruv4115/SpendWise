import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
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
/// The ring is drawn once per month and then left alone. It sweeps in from
/// nothing the first time a month is shown — the motion says "these figures
/// are being drawn for you now" — and cross-fades when the same month's
/// figures change under it, which is what a recategorisation does. Re-sweeping
/// there would claim the month had been reloaded, and a ring caught
/// mid-morph between two sets of angles is a ring that can be misread.
///
/// Takes plain data and no providers, so it can be golden-tested.
class SpendDonut extends StatefulWidget {
  const SpendDonut({
    super.key,
    required this.month,
    required this.slices,
    this.onSliceTap,
  });

  /// `YYYY-MM`. Which month these slices belong to — the chart sweeps when
  /// this changes and cross-fades when only [slices] does.
  final String month;

  /// Largest first, drawn clockwise from twelve o'clock.
  final List<CategorySlice> slices;

  /// Called with a slice that stands for one category. A fold has no single
  /// feed to open, so it is not tappable.
  final ValueChanged<CategorySlice>? onSliceTap;

  static const double holeRadius = 52;
  static const double ringWidth = 36;
  static const double diameter = 2 * (holeRadius + ringWidth);

  /// The fold wears the theme's neutral: it is "everything else", not an
  /// identity.
  static Color colourOf(CategorySlice slice, ColorScheme scheme) {
    final argb = slice.argb;
    return argb == null ? scheme.outline : Color(argb);
  }

  @override
  State<SpendDonut> createState() => _SpendDonutState();
}

class _SpendDonutState extends State<SpendDonut> {
  /// Whether the ring about to be built draws itself from nothing.
  bool _sweep = true;

  @override
  void didUpdateWidget(SpendDonut oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sweep = widget.month != oldWidget.month;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
              height: SpendDonut.diameter,
              // Any change of figures is a new ring, so the old one fades
              // out beneath the new one instead of morphing into it. The
              // default layout is deliberate: AnimatedSwitcher matches the
              // ring on its way out by key, and a wrapper of our own around
              // it would break that match and rebuild it mid-fade.
              child: AnimatedSwitcher(
                duration: motionDuration(context, Motion.crossFade),
                child: _Ring(
                  key: ValueKey(
                    '${widget.month}|${Object.hashAll(widget.slices)}',
                  ),
                  slices: widget.slices,
                  sweep: _sweep,
                  onSliceTap: widget.onSliceTap,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final slice in widget.slices)
          _LegendRow(
            slice: slice,
            colour: SpendDonut.colourOf(slice, scheme),
            onTap: slice.isFold || widget.onSliceTap == null
                ? null
                : () => widget.onSliceTap!(slice),
          ),
      ],
    );
  }
}

/// One drawing of the ring.
///
/// Its own widget, and its own key, so a change of figures replaces it rather
/// than animating it: the cross-fade above is between two of these.
class _Ring extends StatefulWidget {
  const _Ring({
    super.key,
    required this.slices,
    required this.sweep,
    required this.onSliceTap,
  });

  /// This ring's own figures. A tap is resolved against these rather than
  /// against the chart's current ones, so a tap that lands on the ring fading
  /// out opens the category that ring is actually drawing.
  final List<CategorySlice> slices;

  /// Whether to draw in from nothing on the first frame.
  final bool sweep;

  final ValueChanged<CategorySlice>? onSliceTap;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.donutSweep,
    // Fully drawn unless the sweep below rewinds it, so a ring that must not
    // animate never spends a frame empty.
    value: 1,
  );

  late final Animation<double> _drawn = CurvedAnimation(
    parent: _controller,
    curve: Motion.enter,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs a context for the motion preference, so not initState. Once only:
    // a text-scale change must not start the sweep again.
    if (_started) return;
    _started = true;
    if (widget.sweep && !reduceMotion(context)) {
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The ring as it stands at [drawn], a fraction of a full turn.
  ///
  /// The slices keep their proportions and the rest of the circle is held
  /// open by one transparent section, so the ring grows clockwise from twelve
  /// instead of every slice swelling at once.
  List<PieChartSectionData> _sections(double drawn, ColorScheme scheme) {
    var total = 0;
    for (final slice in widget.slices) {
      total += slice.paise;
    }

    return [
      for (final slice in widget.slices)
        PieChartSectionData(
          value: slice.paise * drawn,
          color: SpendDonut.colourOf(slice, scheme),
          radius: SpendDonut.ringWidth,
          showTitle: false,
        ),
      if (drawn < 1 && total > 0)
        PieChartSectionData(
          value: total * (1 - drawn),
          color: Colors.transparent,
          radius: SpendDonut.ringWidth,
          showTitle: false,
        ),
    ];
  }

  void _onTouch(FlTouchEvent event, PieTouchResponse? response) {
    final onTap = widget.onSliceTap;
    if (onTap == null || event is! FlTapUpEvent) return;

    final index = response?.touchedSection?.touchedSectionIndex ?? -1;
    if (index < 0 || index >= widget.slices.length) return;
    final slice = widget.slices[index];
    if (!slice.isFold) onTap(slice);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _drawn,
      builder: (context, _) => PieChart(
        PieChartData(
          sections: _sections(_drawn.value, scheme),
          centerSpaceRadius: SpendDonut.holeRadius,
          sectionsSpace: 2,
          startDegreeOffset: -90,
          pieTouchData: PieTouchData(
            enabled: widget.onSliceTap != null,
            touchCallback: _onTouch,
          ),
        ),
        // The sweep is this widget's own; fl_chart is handed finished
        // figures each frame and must not animate towards them as well.
        duration: Duration.zero,
      ),
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
