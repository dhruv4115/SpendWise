import 'package:spendwise/core/cache/offline_cache.dart';

/// In-memory stand-in for the file cache.
///
/// Holds exactly what the real one holds — an entry per key, with the month
/// it belongs to — and evicts on the same rule, so a test that fills it past
/// three months sees what a device would.
class FakeOfflineCache implements OfflineCache {
  FakeOfflineCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, CacheEntry> entries = {};
  final Map<String, DateTime> _savedMonths = {};

  int writeCount = 0;
  int readCount = 0;

  /// Puts a payload in as if it had been saved [age] ago, for a test that
  /// needs a warm cache before the app starts.
  void seed(
    String key,
    Map<String, Object?> payload, {
    Duration age = Duration.zero,
  }) {
    final savedAt = _now().subtract(age);
    entries[key] = CacheEntry(savedAt: savedAt, payload: payload);
    final month = monthOfCacheKey(key);
    if (month != null) _savedMonths[month] = savedAt;
  }

  /// Puts something unreadable in, the way a half-written file would be.
  void corrupt(String key) {
    entries.remove(key);
  }

  @override
  Future<CacheEntry?> read(String key) async {
    readCount += 1;
    if (monthOfCacheKey(key) == null) return null;
    return entries[key];
  }

  @override
  Future<void> write(String key, Map<String, Object?> payload) async {
    final month = monthOfCacheKey(key);
    if (month == null) return;

    writeCount += 1;
    final savedAt = _now();
    entries[key] = CacheEntry(savedAt: savedAt, payload: payload);
    _savedMonths[month] = savedAt;

    for (final stale in _newestFirst().skip(maxCachedMonths)) {
      _savedMonths.remove(stale);
      entries
        ..remove(transactionsCacheKey(stale))
        ..remove(summaryCacheKey(stale));
    }
  }

  @override
  Future<List<String>> months() async => _newestFirst();

  /// Newest write first, ties broken by the month, exactly as the file cache
  /// orders them.
  List<String> _newestFirst() {
    return _savedMonths.keys.toList()
      ..sort((a, b) {
        final byTime = _savedMonths[b]!.compareTo(_savedMonths[a]!);
        return byTime != 0 ? byTime : b.compareTo(a);
      });
  }

  @override
  Future<void> clear() async {
    entries.clear();
    _savedMonths.clear();
  }
}
