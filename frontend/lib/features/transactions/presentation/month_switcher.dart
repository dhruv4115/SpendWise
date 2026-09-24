import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_format.dart';
import '../../overview/state/summary_provider.dart';
import '../state/feed_provider.dart';
import '../state/month_provider.dart';

/// The month strip above the feed and the Overview.
///
/// One page per month the app offers, swipeable, with an arrow at each end
/// for anyone who would rather tap — or has to. Whatever moves it, the month
/// it lands on is written to [monthProvider], which is the one place the rest
/// of the app asks; and whatever else moves that month — a deep link, the
/// donut, a tap on a neighbouring page — slides the strip to match.
///
/// The months either side are pre-warmed: their feed and summary are watched
/// from here, so they are fetched before the swipe rather than during it, and
/// [residentMonthsProvider] keeps the recent ones from being dropped in
/// between. That is what makes a step backwards a rebuild instead of a round
/// trip.
class MonthSwitcher extends ConsumerStatefulWidget {
  const MonthSwitcher({
    super.key,
    this.warmFeed = false,
    this.warmSummary = false,
  });

  /// What to load for the months either side.
  ///
  /// Each screen asks for what it draws: warming a neighbour's transactions
  /// from the Overview would spend a customer's data on rows that screen
  /// never shows, and warming its summary from the feed would do the same in
  /// reverse.
  final bool warmFeed;
  final bool warmSummary;

  /// How wide one month is, as a fraction of the strip: less than half, so
  /// the months either side peek in and the strip reads as swipeable.
  static const double viewportFraction = 0.44;

  static const Duration slide = Duration(milliseconds: 240);

  @override
  ConsumerState<MonthSwitcher> createState() => _MonthSwitcherState();
}

class _MonthSwitcherState extends ConsumerState<MonthSwitcher> {
  late final PageController _pages = PageController(
    initialPage: _indexOf(ref.read(monthProvider)),
    viewportFraction: MonthSwitcher.viewportFraction,
  );

  int _indexOf(String month) {
    final months = ref.read(monthWindowProvider);
    final index = months.indexOf(month);
    // A month outside the window cannot be selected, so the strip opens on
    // the newest rather than on nothing.
    return index < 0 ? months.length - 1 : index;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// A page the customer swiped to.
  void _onPageChanged(int index) {
    final months = ref.read(monthWindowProvider);
    if (index < 0 || index >= months.length) return;
    ref.read(monthProvider.notifier).set(months[index]);
  }

  /// Brings [index] into view after something else changed the month.
  void _show(int index) {
    if (!_pages.hasClients || index < 0) return;
    final showing = _pages.page?.round() ?? _pages.initialPage;
    if (showing == index) return;

    if (MediaQuery.of(context).disableAnimations) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: MonthSwitcher.slide,
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Loads the months either side.
  ///
  /// Only *whether* they have arrived is watched, so a neighbour landing
  /// rebuilds the strip once rather than on every page of it.
  void _prewarm(List<String> months, int index) {
    for (final step in const [-1, 1]) {
      final neighbour = index + step;
      if (neighbour < 0 || neighbour >= months.length) continue;

      final month = months[neighbour];
      if (widget.warmSummary) {
        ref.watch(summaryProvider(month).select((summary) => summary.hasValue));
      }
      if (widget.warmFeed) {
        ref.watch(
          feedProvider(FeedKey(month: month)).select((feed) => feed.hasValue),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = ref.watch(monthWindowProvider);
    final month = ref.watch(monthProvider);
    final index = months.indexOf(month);

    // A month changed anywhere else — the donut, a deep link — slides the
    // strip after this frame, when the controller has been laid out.
    ref.listen<String>(monthProvider, (_, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show(months.indexOf(next));
      });
    });
    _prewarm(months, index);

    // Grows with the customer's text rather than clipping it.
    final labelSize = theme.textTheme.titleMedium?.fontSize ?? 16;
    final height = math.max(
        56.0, MediaQuery.textScalerOf(context).scale(labelSize) * 1.5 + 24);

    return SizedBox(
      height: height,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: index <= 0
                ? null
                : () => ref.read(monthProvider.notifier).previous(),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: months.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, page) => _MonthPage(
                month: months[page],
                isSelected: page == index,
                onTap: () => ref.read(monthProvider.notifier).set(months[page]),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            // Nothing can have happened after the current month.
            onPressed: index < 0 || index >= months.length - 1
                ? null
                : () => ref.read(monthProvider.notifier).next(),
          ),
        ],
      ),
    );
  }
}

/// One month on the strip. The selected one is filled and bold as well as
/// coloured, and says so to a screen reader.
class _MonthPage extends StatelessWidget {
  const _MonthPage({
    required this.month,
    required this.isSelected,
    required this.onTap,
  });

  final String month;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = monthKeyLabel(month);

    return Semantics(
      button: true,
      selected: isSelected,
      label: isSelected ? '$label, showing' : label,
      excludeSemantics: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Material(
            color: isSelected ? scheme.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isSelected ? null : onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                // Scaled down rather than cut: a half-written month is worse
                // than a small one.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isSelected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
