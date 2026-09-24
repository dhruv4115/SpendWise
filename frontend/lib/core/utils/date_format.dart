/// Date helpers. The wire format is always ISO-8601 UTC; conversion to local
/// time happens exactly once, in a model's `fromJson`, through [isoUtcToLocal].
library;

import 'package:intl/intl.dart';

final RegExp _monthKeyPattern = RegExp(r'^(\d{4})-(\d{2})$');

final DateFormat _dayMonth = DateFormat('d MMM');
final DateFormat _dayMonthYear = DateFormat('d MMM y');
final DateFormat _monthLabel = DateFormat('MMMM y');
final DateFormat _dateTime = DateFormat('EEE, d MMM y, h:mm a');
final DateFormat _time = DateFormat('h:mm a');

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

/// The month the server files [at] under.
///
/// The API buckets by UTC month, so a payment at 1 a.m. IST on 1 October is a
/// September transaction there — and it is September's summary that moves
/// when it is recategorised. This reads the UTC calendar; it does not convert
/// the model, which stays in local time.
String serverMonthKey(DateTime at) => monthKey(at.toUtc());

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

/// `DateTime(2026, 9, 12)` -> `'12 Sep'`, for chart axes, tooltips and table
/// rows where the month is already on screen.
String shortDateLabel(DateTime date) => _dayMonth.format(date);

/// Midnight at the start of [at]'s local day.
DateTime dateOnly(DateTime at) => DateTime(at.year, at.month, at.day);

/// The last millisecond of [day]'s local day: an inclusive upper bound that
/// still takes in a payment at 11:59 p.m. Milliseconds rather than
/// microseconds, because that is as fine as the server's clock goes.
DateTime endOfDay(DateTime day) =>
    DateTime(day.year, day.month, day.day, 23, 59, 59, 999);

/// A date filter in words, for its chip and the sheet's date button:
/// `1 Sep – 12 Sep`, `5 Sep` for a single day, `From 1 Sep`, `Until 12 Sep`,
/// or `Any date`.
String dateRangeLabel(DateTime? from, DateTime? to) {
  return switch ((from, to)) {
    (null, null) => 'Any date',
    (final DateTime start, null) => 'From ${shortDateLabel(start)}',
    (null, final DateTime end) => 'Until ${shortDateLabel(end)}',
    (final DateTime start, final DateTime end)
        when dateOnly(start) == dateOnly(end) =>
      shortDateLabel(start),
    (final DateTime start, final DateTime end) =>
      '${shortDateLabel(start)} – ${shortDateLabel(end)}',
  };
}

/// When a saved copy was written, as the stale-data banner says it: `2:14 pm`
/// today, `yesterday at 2:14 pm`, or `12 Sep at 2:14 pm` before that.
///
/// Lower-case am/pm, and never a bare time for something saved days ago — a
/// customer reading "2:14 pm" would assume today.
String savedAtLabel(DateTime at, {DateTime? now}) {
  final time = _time.format(at).toLowerCase();
  final today = dateOnly(now ?? DateTime.now());
  final days = today.difference(dateOnly(at)).inDays;

  if (days == 0) return time;
  if (days == 1) return 'yesterday at $time';
  return '${shortDateLabel(at)} at $time';
}

/// A transaction's moment in full, for its detail screen:
/// `Tue, 22 Sep 2026, 12:00 PM`.
String dateTimeLabel(DateTime at) => _dateTime.format(at);

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
