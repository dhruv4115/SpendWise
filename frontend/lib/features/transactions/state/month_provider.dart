import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_format.dart';

/// "Now", as a seam. Everything that asks what month or day it is goes through
/// here, so a test pins the calendar instead of racing it.
final Provider<DateTime Function()> clockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// The newest month that can have transactions in it: this one.
final Provider<String> latestMonthProvider = Provider<String>(
  (ref) => monthKey(ref.watch(clockProvider)()),
);

/// The month the app is looking at, as a `YYYY-MM` key.
///
/// Starts on the current month. Never moves past it: a future month can only
/// ever be empty, and an arrow that leads to a blank page is a dead end.
class MonthNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(latestMonthProvider);

  void next() => set(addMonths(state, 1));

  void previous() => set(addMonths(state, -1));

  /// Jumps to [month]. A month after the current one lands on the current one.
  ///
  /// Throws [FormatException] if [month] is not `YYYY-MM`.
  void set(String month) {
    parseMonthKey(month);
    final latest = ref.read(latestMonthProvider);
    // Zero-padded YYYY-MM keys sort chronologically as plain strings.
    state = month.compareTo(latest) > 0 ? latest : month;
  }
}

final NotifierProvider<MonthNotifier, String> monthProvider =
    NotifierProvider<MonthNotifier, String>(MonthNotifier.new);
