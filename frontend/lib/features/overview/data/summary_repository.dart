import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/offline_cache.dart';
import '../../../core/errors/bank_error.dart';
import '../../../core/network/api_client.dart';
import '../domain/month_summary.dart';

/// Everything the app reads from `/summary`. Throws [BankError] only.
class SummaryRepository {
  SummaryRepository({required Dio dio, required OfflineCache cache})
      : _dio = dio,
        _cache = cache;

  static const String summaryPath = '/summary';

  final Dio _dio;
  final OfflineCache _cache;

  /// The server's roll-up of [month] (`YYYY-MM`). Network only.
  Future<MonthSummary> fetchSummary(String month) {
    return _dio.getObject(
      summaryPath,
      query: {'month': month},
      parse: MonthSummary.fromJson,
      malformedCode: 'MALFORMED_SUMMARY',
    );
  }

  /// The saved copy of [month], or null when there is none.
  ///
  /// Carries when it was saved, so the caller can decide whether it is worth
  /// showing before the network answers.
  Future<Cached<MonthSummary>?> cachedSummary(String month) =>
      _cache.readAs(summaryCacheKey(month), MonthSummary.fromJson);

  /// Fetches [month] and saves it.
  ///
  /// A failure the network caused comes back as the saved copy marked stale
  /// rather than as a throw — a month the customer looked at yesterday is
  /// worth more than an error screen. With nothing saved, the [BankError]
  /// stands.
  Future<Cached<MonthSummary>> refreshSummary(String month) {
    return _cache.refreshInto(
      summaryCacheKey(month),
      fetch: () => fetchSummary(month),
      encode: (summary) => summary.toJson(),
      decode: MonthSummary.fromJson,
    );
  }
}

final Provider<SummaryRepository> summaryRepositoryProvider =
    Provider<SummaryRepository>(
  (ref) => SummaryRepository(
    dio: ref.watch(dioProvider),
    cache: ref.watch(offlineCacheProvider),
  ),
);
