/// The read-through cache that lets a signed-in customer open the app on a
/// train and still see their last three months.
///
/// Only two kinds of thing are ever kept here — a month's first page of
/// transactions and a month's summary — and the key shape says so. There is
/// no key a token, a PIN or a set of credentials could be written under, and
/// [_cacheKeyPattern] rejects anything that is not one of the two. The
/// session lives in the keystore and nowhere else.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../errors/bank_error.dart';

/// How long a saved copy is worth showing before the network is asked again.
const Duration cacheTtl = Duration(hours: 24);

/// How many months are kept. The oldest is evicted on write, so the cache
/// cannot grow with the number of months a customer browses.
const int maxCachedMonths = 3;

/// `txns_2026-09` — one month's first page.
String transactionsCacheKey(String month) => 'txns_$month';

/// `summary_2026-09` — one month's roll-up.
String summaryCacheKey(String month) => 'summary_$month';

final RegExp _cacheKeyPattern = RegExp(r'^(txns|summary)_(\d{4}-\d{2})$');

/// The month a key belongs to, or null when the key is not one this cache
/// will hold. Eviction works in months, not in keys: a month's page and its
/// summary arrive together and go together.
String? monthOfCacheKey(String key) =>
    _cacheKeyPattern.firstMatch(key)?.group(2);

/// One saved response.
@immutable
class CacheEntry {
  const CacheEntry({required this.savedAt, required this.payload});

  /// When this copy was written. Local time, as the banner shows it.
  final DateTime savedAt;

  /// Exactly what the server sent, as decoded JSON.
  final Map<String, Object?> payload;

  Duration ageAt(DateTime now) => now.difference(savedAt);

  /// Whether it is still worth showing without asking the network first.
  bool isFreshAt(DateTime now) => ageAt(now) < cacheTtl;

  bool get isFresh => isFreshAt(DateTime.now());

  @override
  String toString() => 'CacheEntry(savedAt: $savedAt)';
}

/// A value, and where it came from.
///
/// [savedAt] is null when the server answered. [isStale] means the request
/// failed and this saved copy is standing in for it — which is the one case
/// the UI tells the customer about.
@immutable
class Cached<T> {
  const Cached(this.value, {this.savedAt, this.isStale = false});

  final T value;
  final DateTime? savedAt;
  final bool isStale;

  bool get isFromCache => savedAt != null;

  /// Whether a saved copy is recent enough to put on screen before the
  /// network is asked. The server's own answer is always fresh.
  bool isFreshAt(DateTime now) =>
      savedAt == null || now.difference(savedAt!) < cacheTtl;

  bool get isFresh => isFreshAt(DateTime.now());

  Cached<T> asStale() => Cached(value, savedAt: savedAt, isStale: true);

  @override
  String toString() => 'Cached(fromCache: $isFromCache, stale: $isStale)';
}

/// The cache, as its callers see it. An in-memory implementation stands in
/// for the real one in tests.
abstract interface class OfflineCache {
  /// The saved copy under [key], or null when there is none, the key is not
  /// one this cache holds, or what was there could not be read.
  Future<CacheEntry?> read(String key);

  /// Saves [payload] under [key] and evicts the oldest month if that takes
  /// the cache past [maxCachedMonths].
  ///
  /// Never throws: a cache that fails a write is a cache miss later, not an
  /// error a customer should see.
  Future<void> write(String key, Map<String, Object?> payload);

  /// The months held, newest save first.
  Future<List<String>> months();

  /// Drops everything. Used when signing out.
  Future<void> clear();
}

/// The cache-then-network border, written once so both repositories cross it
/// the same way.
extension CachedReads on OfflineCache {
  /// The saved copy under [key], decoded, or null when there is none or it
  /// can no longer be read as a [T] — a payload written by an older build of
  /// the app is a miss, not a crash.
  Future<Cached<T>?> readAs<T>(
    String key,
    T Function(Map<String, Object?> json) decode,
  ) async {
    final entry = await read(key);
    if (entry == null) return null;
    try {
      return Cached(decode(entry.payload), savedAt: entry.savedAt);
    } on FormatException {
      return null;
    }
  }

  /// Asks the network, saves what comes back, and falls back to the saved
  /// copy when the bank could not be reached at all.
  ///
  /// The fallback is what lets a customer on a train see last week's month.
  /// It is offered for a [NetworkError] and nothing else: a 500 means the
  /// bank answered and is broken, a 422 means the request was wrong, and
  /// quietly showing yesterday's figures instead of saying so would turn
  /// every fault into a silent one.
  Future<Cached<T>> refreshInto<T>(
    String key, {
    required Future<T> Function() fetch,
    required Map<String, Object?> Function(T value) encode,
    required T Function(Map<String, Object?> json) decode,
  }) async {
    try {
      final value = await fetch();
      await write(key, encode(value));
      return Cached(value);
    } on NetworkError {
      final saved = await readAs(key, decode);
      if (saved == null) rethrow;
      return saved.asStale();
    }
  }
}

/// JSON files under `<application documents>/cache/`.
///
/// Every method swallows its own failures. A missing plugin, a full disk or a
/// file half-written when the app was killed all degrade to "no cached copy",
/// which every caller already handles.
class FileOfflineCache implements OfflineCache {
  FileOfflineCache({Future<Directory> Function()? directory})
      : _resolve = directory ?? offlineCacheDirectory;

  /// Records which months are held and when each was last written, so
  /// evicting the oldest does not mean reading back a megabyte of
  /// transactions to find out how old it is.
  static const String indexFile = 'index.json';

  final Future<Directory> Function() _resolve;

  @override
  Future<CacheEntry?> read(String key) async {
    if (monthOfCacheKey(key) == null) return null;

    try {
      final file = await _fileFor(key);
      if (!file.existsSync()) return null;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('not an object');

      final savedAt = DateTime.parse('${decoded['savedAt']}');
      final payload = decoded['payload'];
      if (payload is! Map) throw const FormatException('no payload');

      return CacheEntry(
        savedAt: savedAt.toLocal(),
        payload: Map<String, Object?>.from(payload),
      );
    } on Object {
      // Half-written, hand-edited or from an older format: throw it away
      // rather than hand a caller something it cannot parse.
      await _delete(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, Object?> payload) async {
    final month = monthOfCacheKey(key);
    assert(month != null, 'Refusing to cache under "$key"');
    if (month == null) return;

    try {
      final directory = await _directory();
      final entry = jsonEncode({
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'payload': payload,
      });
      // Written beside the real file and moved into place, so a kill
      // mid-write leaves the previous copy rather than a broken one.
      final temporary = File('${directory.path}/$key.json.part');
      await temporary.writeAsString(entry, flush: true);
      await temporary.rename('${directory.path}/$key.json');

      await _touch(month);
    } on Object {
      // Nothing to do and nobody to tell: the next read is simply a miss.
    }
  }

  @override
  Future<List<String>> months() async =>
      List.unmodifiable(_newestFirst(await _readIndex()));

  /// Newest write first, ties broken by the month itself.
  ///
  /// Two writes can land in the same microsecond, and without a tiebreak the
  /// month that survives eviction would depend on the sort's internals.
  static List<String> _newestFirst(Map<String, DateTime> index) {
    return index.keys.toList()
      ..sort((a, b) {
        final byTime = index[b]!.compareTo(index[a]!);
        return byTime != 0 ? byTime : b.compareTo(a);
      });
  }

  @override
  Future<void> clear() async {
    try {
      final directory = await _directory();
      if (directory.existsSync()) await directory.delete(recursive: true);
    } on Object {
      // Already gone, or never there.
    }
  }

  /// Marks [month] as the most recently written and evicts anything past
  /// [maxCachedMonths].
  Future<void> _touch(String month) async {
    final index = await _readIndex();
    index[month] = DateTime.now();

    for (final stale in _newestFirst(index).skip(maxCachedMonths)) {
      index.remove(stale);
      await _delete(transactionsCacheKey(stale));
      await _delete(summaryCacheKey(stale));
    }

    await _writeIndex(index);
  }

  Future<Map<String, DateTime>> _readIndex() async {
    try {
      final file = await _fileFor(indexFile, extension: '');
      if (!file.existsSync()) return {};

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('not an object');

      return {
        for (final entry in decoded.entries)
          '${entry.key}': DateTime.parse('${entry.value}').toLocal(),
      };
    } on Object {
      // Without the index there is no way to know what to evict, and a cache
      // that cannot be pruned is worse than an empty one.
      await clear();
      return {};
    }
  }

  Future<void> _writeIndex(Map<String, DateTime> index) async {
    final file = await _fileFor(indexFile, extension: '');
    await file.writeAsString(
      jsonEncode({
        for (final entry in index.entries)
          entry.key: entry.value.toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> _delete(String key) async {
    try {
      final file = await _fileFor(key);
      if (file.existsSync()) await file.delete();
    } on Object {
      // Nothing to do: it is already unreadable.
    }
  }

  Future<File> _fileFor(String name, {String extension = '.json'}) async =>
      File('${(await _directory()).path}/$name$extension');

  Future<Directory> _directory() async {
    final directory = await _resolve();
    if (!directory.existsSync()) await directory.create(recursive: true);
    return directory;
  }
}

/// Where everything this app caches on disk lives.
///
/// Shared rather than private, because the cache is not the only thing that
/// belongs here: the budget-alert dedupe store writes its own small file
/// beside these, for the same reason — it is disposable, it is not a secret,
/// and it must not go anywhere near the keystore.
Future<Directory> offlineCacheDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  return Directory('${documents.path}/cache');
}

/// The app's cache. Overridden in tests with an in-memory fake.
final Provider<OfflineCache> offlineCacheProvider =
    Provider<OfflineCache>((ref) => FileOfflineCache());
