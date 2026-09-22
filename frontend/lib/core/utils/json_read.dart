/// Typed readers for decoded JSON.
///
/// Every `fromJson` in the app goes through these, so a malformed payload
/// fails in one predictable way — a [FormatException] naming the field — rather
/// than as a cast error thrown from somewhere inside a widget build.
///
/// Nothing here is `dynamic`: the readers take `Map<String, Object?>`, which a
/// `Map<String, dynamic>` from `jsonDecode` satisfies. That keeps `dynamic`
/// confined to the `fromJson` signatures themselves.
library;

import 'date_format.dart';

Never _malformed(String key, Object? value, String expected) {
  throw FormatException(
    'Field "$key" should be $expected, got ${value.runtimeType}',
  );
}

/// A non-empty string. An empty one is treated as missing: the API never
/// deliberately sends `""` for an id, a name or a category.
String readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  _malformed(key, value, 'a non-empty string');
}

/// A whole number.
///
/// A JSON `1200.0` decodes to a double and is rejected rather than rounded:
/// money is integer paise, and a fractional amount means the payload is wrong.
int readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  _malformed(key, value, 'a whole number');
}

int readIntOr(Map<String, Object?> json, String key, int fallback) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is int) return value;
  _malformed(key, value, 'a whole number or null');
}

bool readBoolOr(Map<String, Object?> json, String key, bool fallback) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is bool) return value;
  _malformed(key, value, 'true or false');
}

/// An ISO-8601 UTC timestamp, returned in local time.
///
/// This is the one place the wire's UTC becomes the device's local time —
/// models store local [DateTime] and never convert again.
DateTime readUtcTimestamp(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    _malformed(key, value, 'an ISO-8601 UTC timestamp');
  }
  try {
    return isoUtcToLocal(value);
  } on FormatException {
    throw FormatException('Field "$key" is not an ISO-8601 timestamp', value);
  }
}

final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A calendar date, `YYYY-MM-DD`, as local midnight.
///
/// A day has no time zone to convert: `2026-09-12` is that day wherever the
/// customer is standing, so it becomes midnight local and stays there.
///
/// `DateTime.parse` does not range-check — it reads `2026-13-01` as January
/// 2027 and `2026-02-31` as 3 March — so the parsed date is formatted back and
/// compared. A day that did not survive the round trip was never a real date.
DateTime readLocalDate(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || !_datePattern.hasMatch(value)) {
    _malformed(key, value, 'a YYYY-MM-DD date');
  }

  final parsed = DateTime.parse(value);
  if (isoLocalDate(parsed) != value) {
    throw FormatException('Field "$key" is not a real calendar date', value);
  }
  return parsed;
}

/// A map of whole numbers, such as `byCategory`.
Map<String, int> readIntMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) _malformed(key, value, 'an object of whole numbers');

  final result = <String, int>{};
  for (final entry in value.entries) {
    final amount = entry.value;
    if (amount is! int) {
      _malformed('$key.${entry.key}', amount, 'a whole number');
    }
    result['${entry.key}'] = amount;
  }
  return result;
}

/// A list of objects, each mapped through [item].
List<T> readObjectList<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?> element) item,
) {
  final value = json[key];
  if (value is! List) _malformed(key, value, 'a list');

  return [
    for (final element in value)
      if (element is Map)
        item(Map<String, Object?>.from(element))
      else
        _malformed(key, element, 'a list of objects'),
  ];
}

/// `DateTime(2026, 9, 12)` -> `'2026-09-12'`, using local date components.
///
/// The inverse of [readLocalDate], for putting a date back on the wire.
String isoLocalDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
