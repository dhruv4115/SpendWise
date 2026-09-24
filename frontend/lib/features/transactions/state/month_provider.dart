import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_format.dart';

/// "Now", as a seam. Everything that asks what month or day it is goes through
/// here, so a test pins the calendar instead of racing it.
final Provider<DateTime Function()> clockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// How far back the app looks.
///
/// Six months and the current one. Further back is not offered: the cache
/// holds three months, the customer's interest drops off a cliff after two,
/// and a strip that scrolls for ever is one nobody reaches the end of.
const int monthsBack = 6;

/// How many months stay in memory at once.
///
/// Three is what makes stepping between this month, last month and the one
/// before it instant, and what stops a customer who has browsed a year from
/// holding a year of transactions in RAM.
const int residentMonths = 3;

/// The newest month that can have transactions in it: this one.
final Provider<String> latestMonthProvider = Provider<String>(
  (ref) => monthKey(ref.watch(clockProvider)()),
);

/// The oldest month the app will show.
final Provider<String> earliestMonthProvider = Provider<String>(
  (ref) => addMonths(ref.watch(latestMonthProvider), -monthsBack),
);

/// Every month on offer, oldest first. The month switcher's pages, in order.
final Provider<List<String>> monthWindowProvider =
    Provider<List<String>>((ref) {
  final latest = ref.watch(latestMonthProvider);
  return List.unmodifiable([
    for (var back = monthsBack; back >= 0; back--) addMonths(latest, -back),
  ]);
});

/// The months whose feed and summary are held open rather than disposed the
/// moment the customer looks elsewhere.
///
/// Read by the providers themselves, so the rule lives in one place and the
/// screens do not have to know it.
final Provider<Set<String>> residentMonthsProvider = Provider<Set<String>>(
  (ref) {
    final latest = ref.watch(latestMonthProvider);
    return Set.unmodifiable({
      for (var back = 0; back < residentMonths; back++)
        addMonths(latest, -back),
    });
  },
);

/// The month the app is looking at, as a `YYYY-MM` key.
///
/// Starts on the current month, and stays inside [monthWindowProvider]:
/// a future month can only ever be empty, and an arrow that leads to a blank
/// page is a dead end.
class MonthNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(latestMonthProvider);

  void next() => set(addMonths(state, 1));

  void previous() => set(addMonths(state, -1));

  /// Jumps to [month], clamped to the window: a month after the current one
  /// lands on the current one, and one further back than the app goes lands
  /// on the oldest it offers.
  ///
  /// Throws [FormatException] if [month] is not `YYYY-MM`.
  void set(String month) {
    parseMonthKey(month);
    final latest = ref.read(latestMonthProvider);
    final earliest = ref.read(earliestMonthProvider);
    // Zero-padded YYYY-MM keys sort chronologically as plain strings.
    if (month.compareTo(latest) > 0) {
      state = latest;
    } else if (month.compareTo(earliest) < 0) {
      state = earliest;
    } else {
      state = month;
    }
  }
}

final NotifierProvider<MonthNotifier, String> monthProvider =
    NotifierProvider<MonthNotifier, String>(MonthNotifier.new);
