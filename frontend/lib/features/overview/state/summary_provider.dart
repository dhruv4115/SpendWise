import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/summary_repository.dart';
import '../domain/month_summary.dart';

/// One month's summary, keyed by `YYYY-MM`.
///
/// A recategorisation moves money between categories, so it invalidates this
/// for the months it touched; the total never changes, only `byCategory`.
final AutoDisposeFutureProviderFamily<MonthSummary, String> summaryProvider =
    FutureProvider.autoDispose.family<MonthSummary, String>(
  (ref, month) => ref.watch(summaryRepositoryProvider).fetchSummary(month),
);
