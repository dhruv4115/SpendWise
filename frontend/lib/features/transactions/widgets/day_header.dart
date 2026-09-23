import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';

/// Widest the day total may render before it is scaled down to fit.
const double _totalMaxWidth = 200;

/// A day's section header: `Today`, `Yesterday` or `12 Sep`, and the signed
/// total of the rows beneath it.
class DayHeader extends StatelessWidget {
  const DayHeader({
    super.key,
    required this.label,
    required this.totalPaise,
    this.raised = false,
  });

  final String label;

  /// Signed like the rows: negative for a day of spending.
  final int totalPaise;

  /// True while rows are scrolling underneath the pinned header.
  final bool raised;

  static const double _verticalPadding = 8;

  static TextStyle _style(ThemeData theme) => theme.textTheme.titleSmall!;

  /// The header's height under the ambient text scale.
  ///
  /// A pinned header has to state its extent before it is laid out, so this
  /// works it out from the same style and forced strut the header renders
  /// with. A hard-coded height would clip the label at a 2.0 text scale.
  static double extentOf(BuildContext context) {
    final style = _style(Theme.of(context));
    final fontSize = style.fontSize ?? 14;
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(fontSize) * (style.height ?? 1);
    // 14 × (20 / 14) is 20.000000000000004 in floating point; the tolerance
    // keeps that from rounding up to a spare pixel.
    return (lineHeight - 0.001).ceilToDouble() + 2 * _verticalPadding;
  }

  static String _spokenTotal(int totalPaise) {
    if (totalPaise < 0) return 'Net spend ${formatPaise(-totalPaise)}';
    if (totalPaise > 0) return 'Net refund ${formatPaise(totalPaise)}';
    return 'Nothing spent';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = _style(theme);
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);

    return Semantics(
      header: true,
      label: '$label. ${_spokenTotal(totalPaise)}.',
      excludeSemantics: true,
      child: Material(
        color: raised ? scheme.surfaceContainer : scheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: _verticalPadding,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(color: scheme.onSurfaceVariant),
                  strutStyle: strut,
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _totalMaxWidth),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    formatSignedPaise(totalPaise),
                    maxLines: 1,
                    softWrap: false,
                    style: style.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: totalPaise > 0
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    strutStyle: strut,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pins a [DayHeader] to the top of its day's section.
///
/// Inside a `SliverMainAxisGroup` the pin lasts only as long as the section
/// does, which is the whole sticky-header effect: the next day's header pushes
/// this one off, with no sticky-header package.
class DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  const DayHeaderDelegate({
    required this.label,
    required this.totalPaise,
    required this.extent,
  });

  final String label;
  final int totalPaise;

  /// From [DayHeader.extentOf].
  final double extent;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // The sliver hands its child loose constraints but reports [extent] as
    // its own size, so the child must fill it exactly or the geometry is
    // invalid.
    return SizedBox.expand(
      child: DayHeader(
        label: label,
        totalPaise: totalPaise,
        raised: overlapsContent || shrinkOffset > 0,
      ),
    );
  }

  @override
  bool shouldRebuild(DayHeaderDelegate oldDelegate) =>
      oldDelegate.label != label ||
      oldDelegate.totalPaise != totalPaise ||
      oldDelegate.extent != extent;
}
