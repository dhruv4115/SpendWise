import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../domain/month_summary.dart';
import '../domain/overview_data.dart';
import 'summary_provider.dart';

/// Everything the Overview draws for [month], derived once per summary.
///
/// A provider rather than a computation in build: the slices, the zero-filled
/// days and both tables are worked out when the numbers change and not when
/// a widget happens to rebuild — a scroll, a theme change or the table
/// toggle reuses the same lists.
///
/// The device's own summary wins once it exists (see [localSummaryProvider]);
/// until then, the server's. Category names and colours come with it, so the
/// first frame of the donut is already the right colours rather than grey
/// then colour. If the categories fail to load, the chart still draws, with
/// readable ids and the neutral colour.
final AutoDisposeProviderFamily<AsyncValue<OverviewData>, String>
    overviewProvider =
    Provider.autoDispose.family<AsyncValue<OverviewData>, String>((ref, month) {
  final local = ref.watch(localSummaryProvider(month)).valueOrNull;
  final source = local != null
      ? AsyncData<MonthSummary>(local)
      : ref.watch(summaryProvider(month));
  final categories = ref.watch(categoriesProvider);

  if (categories.isLoading && !categories.hasValue && !source.hasError) {
    return const AsyncLoading<OverviewData>();
  }
  final known = categories.valueOrNull ?? const <Category>[];
  // A refresh arrives as data that is also loading, and whenData keeps both:
  // pull-to-refresh draws over the charts rather than swapping them for a
  // skeleton.
  return source.whenData((summary) => OverviewData.from(summary, known));
});

/// Whether the Overview shows its charts as tables — the screen-reader and
/// low-vision alternative. Kept for the session, so the choice survives a
/// month change or a trip to another tab.
class ChartTablesNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set({required bool showTables}) => state = showTables;
}

final NotifierProvider<ChartTablesNotifier, bool> chartTablesProvider =
    NotifierProvider<ChartTablesNotifier, bool>(ChartTablesNotifier.new);
