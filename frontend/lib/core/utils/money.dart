/// Money is always signed integer paise. These are the only functions allowed
/// to turn paise into text, and none of them takes a BuildContext.
///
/// Sign convention: debits (spends) are negative, credits (refunds) positive.
library;

import 'package:intl/intl.dart';

const String rupeeSign = '₹';

/// Indian digit grouping: 1,23,456 rather than 123,456.
final NumberFormat _grouped = NumberFormat.decimalPattern('en_IN');

/// `-123456` -> `-₹1,234.56`, `123456` -> `₹1,234.56`.
String formatPaise(int paise) {
  final magnitude = paise.abs();
  final rupees = _grouped.format(magnitude ~/ 100);
  final fraction = (magnitude % 100).toString().padLeft(2, '0');
  final sign = paise < 0 ? '-' : '';
  return '$sign$rupeeSign$rupees.$fraction';
}

/// Always carries an explicit sign, for rows where a refund must not be
/// mistaken for a spend: `+₹450.00` / `-₹450.00`. Zero has no sign.
String formatSignedPaise(int paise) {
  if (paise == 0) return formatPaise(0);
  return paise > 0 ? '+${formatPaise(paise)}' : formatPaise(paise);
}

/// Parses user input into paise, or null when it is not a usable amount.
///
/// Accepts an optional rupee sign, thousands separators and up to two
/// decimals: `1,234.5`, `₹1234.56`, `-99`. Rejects anything else, including
/// three decimals (`12.345`), stray text and an empty field.
int? parseRupeesToPaise(String? input) {
  if (input == null) return null;

  final cleaned = input
      .replaceAll(rupeeSign, '')
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .trim();
  if (cleaned.isEmpty) return null;

  final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;

  final rupees = int.tryParse(match.group(2)!);
  if (rupees == null) return null; // Longer than an int64 can hold.

  final fraction = int.parse((match.group(3) ?? '').padRight(2, '0'));
  final paise = rupees * 100 + fraction;
  return match.group(1) == '-' ? -paise : paise;
}

/// Paise as a customer would type them back into an amount field: `50000`
/// -> `500`, `25050` -> `250.50`. No rupee sign and no grouping, so
/// [parseRupeesToPaise] reads the text straight back to the same paise.
String paiseToInput(int paise) {
  final magnitude = paise.abs();
  final sign = paise < 0 ? '-' : '';
  final rupees = magnitude ~/ 100;
  final fraction = magnitude % 100;
  if (fraction == 0) return '$sign$rupees';
  return '$sign$rupees.${fraction.toString().padLeft(2, '0')}';
}

/// An amount filter in words, for the chip that shows it: `₹500.00 –
/// ₹1,000.00`, `At least ₹500.00`, `Up to ₹1,000.00`, or `Any amount`.
String amountRangeLabel(int? minPaise, int? maxPaise) {
  return switch ((minPaise, maxPaise)) {
    (null, null) => 'Any amount',
    (final int min, null) => 'At least ${formatPaise(min)}',
    (null, final int max) => 'Up to ${formatPaise(max)}',
    (final int min, final int max) when min == max => formatPaise(min),
    (final int min, final int max) =>
      '${formatPaise(min)} – ${formatPaise(max)}',
  };
}

/// Short form for chart axes and tiles: `₹999`, `₹12.3K`, `₹1.2L`, `₹3.4Cr`.
///
/// Truncates rather than rounds, so a value never appears to cross the next
/// boundary (99,999 rupees reads `₹99.9K`, not `₹100K`).
String abbreviate(int paise) {
  final rupees = paise.abs() ~/ 100;
  final sign = paise < 0 ? '-' : '';

  if (rupees < 1000) {
    return '$sign$rupeeSign$rupees';
  }
  if (rupees < 100000) {
    return '$sign$rupeeSign${_oneDecimal(rupees, 1000)}K';
  }
  if (rupees < 10000000) {
    return '$sign$rupeeSign${_oneDecimal(rupees, 100000)}L';
  }
  return '$sign$rupeeSign${_oneDecimal(rupees, 10000000)}Cr';
}

/// `value / unit` truncated to one decimal, with a bare `.0` dropped.
String _oneDecimal(int value, int unit) {
  final whole = value ~/ unit;
  final tenths = (value % unit) * 10 ~/ unit;
  return tenths == 0 ? '$whole' : '$whole.$tenths';
}
