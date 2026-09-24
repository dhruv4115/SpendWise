/// Remembers which budget alerts have already been fired, so a customer is
/// told once that they have passed 80% of their food budget — not once every
/// time the app refreshes the figure.
///
/// Kept in the offline cache directory rather than the keystore: a fired-alert
/// key is a month, a category and a percentage. There is nothing secret in it,
/// it can be thrown away at any time, and the keystore is for the session
/// token alone.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/offline_cache.dart';

/// How many months of fired alerts are kept. The same three the offline cache
/// holds: further back, a key can never be consulted again, because the month
/// it names has scrolled out of the window the app offers.
const int maxAlertMonths = 3;

/// `2026-09|food|80` — one alert, for one category, in one month.
///
/// The month is part of the key, which is what makes October start again from
/// nothing without a single line of resetting code.
String alertKey({
  required String month,
  required String category,
  required int threshold,
}) =>
    '$month|$category|$threshold';

final RegExp _alertKeyPattern = RegExp(r'^(\d{4}-\d{2})\|([^|]+)\|(\d{1,3})$');

/// The month an alert key belongs to, or null when the key is not one of
/// ours — a hand-edited file, or one written by an older build.
String? monthOfAlertKey(String key) =>
    _alertKeyPattern.firstMatch(key)?.group(1);

/// The set of alerts already fired, as its caller sees it.
abstract interface class AlertDedupeStore {
  /// Records [key] and answers whether it is new.
  ///
  /// True exactly once per key: the caller fires the notification only when
  /// it gets a true, so an alert cannot be shown twice however often the
  /// budgets are refetched.
  Future<bool> markFired(String key);

  /// Every key recorded, for the months still kept.
  Future<Set<String>> fired();

  /// Forgets everything. Used when signing out, so the next customer on this
  /// device is not silently denied their own first alert.
  Future<void> clear();
}

/// One JSON file of keys, beside the cached months.
///
/// Reads and writes are swallowed the way the cache's are, but they fail in
/// opposite directions and both are safe: a read that fails starts from an
/// empty set, so at worst an alert is repeated once; a write that fails
/// leaves the key in memory, so it is not repeated until the app restarts.
/// Neither can lose an alert that has not been shown.
class FileAlertDedupeStore implements AlertDedupeStore {
  FileAlertDedupeStore({Future<Directory> Function()? directory})
      : _resolve = directory ?? offlineCacheDirectory;

  static const String fileName = 'budget_alerts.json';

  final Future<Directory> Function() _resolve;

  /// Loaded once and then kept, so two alerts landing in the same frame
  /// cannot both read an empty file and both decide they are first.
  Future<Set<String>>? _keys;

  @override
  Future<bool> markFired(String key) async {
    final keys = await _load();
    if (!keys.add(key)) return false;
    await _save(keys);
    return true;
  }

  @override
  Future<Set<String>> fired() async => Set.unmodifiable(await _load());

  @override
  Future<void> clear() async {
    _keys = Future.value(<String>{});
    try {
      final file = await _file();
      if (file.existsSync()) await file.delete();
    } on Object {
      // Already gone, or never written.
    }
  }

  Future<Set<String>> _load() {
    return _keys ??= () async {
      try {
        final file = await _file();
        if (!file.existsSync()) return <String>{};

        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! List) throw const FormatException('not a list');
        return {
          for (final entry in decoded)
            if (entry is String && monthOfAlertKey(entry) != null) entry,
        };
      } on Object {
        // Unreadable is the same as empty: the worst it costs is one repeated
        // alert, and refusing to start would cost every alert after it.
        return <String>{};
      }
    }();
  }

  /// Writes [keys], dropping the months past [maxAlertMonths] first.
  ///
  /// `YYYY-MM` keys sort chronologically as plain strings, so the newest
  /// months are simply the last ones.
  Future<void> _save(Set<String> keys) async {
    final months = {for (final key in keys) monthOfAlertKey(key)!}.toList()
      ..sort();
    final kept = months.length <= maxAlertMonths
        ? months.toSet()
        : months.sublist(months.length - maxAlertMonths).toSet();
    keys.removeWhere((key) => !kept.contains(monthOfAlertKey(key)!));

    try {
      final file = await _file();
      // Written beside the real file and moved into place, so a kill
      // mid-write cannot leave half a list behind.
      final temporary = File('${file.path}.part');
      await temporary.writeAsString(jsonEncode(keys.toList()), flush: true);
      await temporary.rename(file.path);
    } on Object {
      // The keys stay in memory; this session still fires each alert once.
    }
  }

  Future<File> _file() async {
    final directory = await _resolve();
    if (!directory.existsSync()) await directory.create(recursive: true);
    return File('${directory.path}/$fileName');
  }
}

/// The app's dedupe store. Overridden in tests with an in-memory one.
final Provider<AlertDedupeStore> alertDedupeStoreProvider =
    Provider<AlertDedupeStore>((ref) => FileAlertDedupeStore());
