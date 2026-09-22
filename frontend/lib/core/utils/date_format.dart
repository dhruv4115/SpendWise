/// Date helpers. The wire format is always ISO-8601 UTC; conversion to local
/// time happens exactly once, in a model's `fromJson`, through [isoUtcToLocal].
library;

import 'package:intl/intl.dart';

final RegExp _monthKeyPattern = RegExp(r'^(\d{4})-(\d{2})$');

final DateFormat _dayMonth = DateFormat('d MMM');
final DateFormat _dayMonthYear = DateFormat('d MMM y');
final DateFormat _monthLabel = DateFormat('MMMM y');

/// `DateTime(2026, 9, 22)` -> `'2026-09'`, using local date components.
String monthKey(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$year-$month';
}

/// `'2026-09'` -> midnight local on the first of that month.
///
/// Throws [FormatException] on anything else, including month 00 or 13.
DateTime parseMonthKey(String key) {
  final match = _monthKeyPattern.firstMatch(key);
  if (match == null) {
    throw FormatException('Expected a YYYY-MM month key', key);
  }
  final month = int.parse(match.group(2)!);
  if (month < 1 || month > 12) {
    throw FormatException('Month must be between 01 and 12', key);
  }
  return DateTime(int.parse(match.group(1)!), month);
}

/// Month arithmetic that rolls across year boundaries in both directions:
/// `addMonths('2026-01', -1) == '2025-12'`.
String addMonths(String key, int delta) {
  final start = parseMonthKey(key);
  return monthKey(DateTime(start.year, start.month + delta));
}

/// `'2026-09'` -> `'September 2026'`, for headers and pickers.
String monthKeyLabel(String key) => _monthLabel.format(parseMonthKey(key));

/// Section header for a day of transactions: `Today`, `Yesterday`, `12 Sep`,
/// or `12 Sep 2025` once the year differs from [now].
String dayHeaderLabel(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final target = DateTime(date.year, date.month, date.day);
  final anchor = DateTime(today.year, today.month, today.day);
  final difference = anchor.difference(target).inDays;

  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  return target.year == anchor.year
      ? _dayMonth.format(target)
      : _dayMonthYear.format(target);
}

/// Parses a wire timestamp and returns local time.
///
/// The contract says timestamps are UTC, so a string that arrives without a
/// zone designator is *read* as UTC rather than silently treated as local.
DateTime isoUtcToLocal(String iso) {
  final parsed = DateTime.parse(iso);
  if (parsed.isUtc) return parsed.toLocal();
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  ).toLocal();
}
