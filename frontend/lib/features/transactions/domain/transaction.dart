import 'package:flutter/foundation.dart';

import '../../../core/utils/json_read.dart';

/// One line on the statement.
///
/// [amountPaise] is signed: a debit is negative, a refund positive. Nothing in
/// the app stores an unsigned amount — "how much was spent" is a question you
/// ask of a set of transactions ([spentPaise]), not a field you read off one.
@immutable
class Transaction {
  const Transaction({
    required this.id,
    required this.merchantRaw,
    required this.merchantName,
    required this.merchantKey,
    required this.category,
    required this.amountPaise,
    required this.at,
    required this.mode,
  });

  /// Parses one wire transaction, converting `at` from UTC to local time.
  ///
  /// Throws [FormatException] when a field is missing or the wrong type —
  /// including a fractional `amountPaise`, which would mean the server has
  /// stopped speaking in paise.
  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: readString(json, 'id'),
      merchantRaw: readString(json, 'merchantRaw'),
      merchantName: readString(json, 'merchantName'),
      merchantKey: readString(json, 'merchantKey'),
      category: readString(json, 'category'),
      amountPaise: readInt(json, 'amountPaise'),
      at: readUtcTimestamp(json, 'at'),
      mode: readString(json, 'mode'),
    );
  }

  final String id;

  /// The descriptor the card network sent, noise and all: `SWIGGY*1234`.
  final String merchantRaw;

  /// The cleaned-up name to show: `Swiggy`.
  final String merchantName;

  /// The normalised grouping key: `swiggy`. Every raw variant of one merchant
  /// shares it.
  final String merchantKey;

  final String category;

  /// Signed paise. Negative is money out, positive is money back.
  final int amountPaise;

  /// Local time. The wire carries UTC; the conversion happened in [fromJson]
  /// and must not happen again.
  final DateTime at;

  /// `UPI`, `CARD`, `NETBANKING`, `CASH` or `AUTOPAY`.
  ///
  /// Kept as the server's string rather than an enum: a payment rail the app
  /// has not heard of must still render, not crash the feed.
  final String mode;

  /// What this line contributes to "spent": the sign flipped, so a refund
  /// subtracts. The single definition of the sign convention.
  int get spentPaise => -amountPaise;

  bool get isRefund => amountPaise > 0;

  Map<String, Object?> toJson() => {
        'id': id,
        'merchantRaw': merchantRaw,
        'merchantName': merchantName,
        'merchantKey': merchantKey,
        'category': category,
        'amountPaise': amountPaise,
        'at': at.toUtc().toIso8601String(),
        'mode': mode,
      };

  Transaction copyWith({
    String? id,
    String? merchantRaw,
    String? merchantName,
    String? merchantKey,
    String? category,
    int? amountPaise,
    DateTime? at,
    String? mode,
  }) {
    return Transaction(
      id: id ?? this.id,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      merchantName: merchantName ?? this.merchantName,
      merchantKey: merchantKey ?? this.merchantKey,
      category: category ?? this.category,
      amountPaise: amountPaise ?? this.amountPaise,
      at: at ?? this.at,
      mode: mode ?? this.mode,
    );
  }

  /// No amount and no merchant: this ends up in logs, and a transaction id
  /// plus a sum is a customer's spending habits.
  @override
  String toString() => 'Transaction(category: $category, mode: $mode)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Transaction &&
          other.id == id &&
          other.merchantRaw == merchantRaw &&
          other.merchantName == merchantName &&
          other.merchantKey == merchantKey &&
          other.category == category &&
          other.amountPaise == amountPaise &&
          other.at == at &&
          other.mode == mode;

  @override
  int get hashCode => Object.hash(
        id,
        merchantRaw,
        merchantName,
        merchantKey,
        category,
        amountPaise,
        at,
        mode,
      );
}
