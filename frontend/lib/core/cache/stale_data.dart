import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two things a month can be showing from its saved copy.
const String transactionsSource = 'transactions';
const String summarySource = 'summary';

/// Which of a month's sources are showing a saved copy, and how old each is.
@immutable
class StaleData {
  const StaleData(this.bySource);

  static const StaleData none = StaleData({});

  /// Source name to when its copy was saved. Empty when everything on screen
  /// came from the server.
  final Map<String, DateTime> bySource;

  bool get isStale => bySource.isNotEmpty;

  /// The oldest copy on screen — the honest one to put in the banner, since
  /// saying "2:14 pm" while half the numbers are from yesterday would be a
  /// smaller truth than the customer needs.
  DateTime? get savedAt {
    DateTime? oldest;
    for (final savedAt in bySource.values) {
      if (oldest == null || savedAt.isBefore(oldest)) oldest = savedAt;
    }
    return oldest;
  }

  @override
  String toString() => 'StaleData(${bySource.keys.join(', ')})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StaleData && mapEquals(other.bySource, bySource);

  @override
  int get hashCode => Object.hashAllUnordered(
        bySource.entries.map((e) => Object.hash(e.key, e.value)),
      );
}

/// Whether the month on screen is being drawn from the cache because the
/// network could not be reached, keyed by `YYYY-MM`.
///
/// The feed and the summary of a month each report for themselves, and the
/// banner asks the month — a customer looking at September wants to be told
/// once, not twice.
class StaleDataNotifier extends FamilyNotifier<StaleData, String> {
  @override
  StaleData build(String month) => StaleData.none;

  /// [savedAt] is when [source]'s copy was saved, or null once [source] has
  /// the server's own answer.
  void report(String source, DateTime? savedAt) {
    final next = {...state.bySource};
    if (savedAt == null) {
      next.remove(source);
    } else {
      next[source] = savedAt;
    }
    if (!mapEquals(next, state.bySource)) state = StaleData(next);
  }
}

final NotifierProviderFamily<StaleDataNotifier, StaleData, String>
    staleDataProvider =
    NotifierProvider.family<StaleDataNotifier, StaleData, String>(
  StaleDataNotifier.new,
);
