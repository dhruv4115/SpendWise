import 'package:flutter/foundation.dart';

import '../../../core/utils/json_read.dart';

/// One merchant's month, rolled up.
///
/// [totalPaise] and [avgPaise] are spend amounts — sign already flipped — so a
/// merchant you were refunded by more than you paid has a negative total and
/// sorts to the bottom, which is correct.
@immutable
class MerchantInsight {
  const MerchantInsight({
    required this.merchantKey,
    required this.merchantName,
    required this.totalPaise,
    required this.visits,
    required this.avgPaise,
    required this.topCategory,
  });

  factory MerchantInsight.fromJson(Map<String, dynamic> json) {
    return MerchantInsight(
      merchantKey: readString(json, 'merchantKey'),
      merchantName: readString(json, 'merchantName'),
      totalPaise: readInt(json, 'totalPaise'),
      visits: readInt(json, 'visits'),
      avgPaise: readInt(json, 'avgPaise'),
      topCategory: readString(json, 'topCategory'),
    );
  }

  final String merchantKey;
  final String merchantName;

  /// Total spent with this merchant over the period.
  final int totalPaise;

  /// How many transactions, refunds included.
  final int visits;

  /// [totalPaise] divided by [visits], truncated. Paise do not subdivide.
  final int avgPaise;

  /// The category this merchant's spend mostly landed in.
  final String topCategory;

  Map<String, Object?> toJson() => {
        'merchantKey': merchantKey,
        'merchantName': merchantName,
        'totalPaise': totalPaise,
        'visits': visits,
        'avgPaise': avgPaise,
        'topCategory': topCategory,
      };

  MerchantInsight copyWith({
    String? merchantKey,
    String? merchantName,
    int? totalPaise,
    int? visits,
    int? avgPaise,
    String? topCategory,
  }) {
    return MerchantInsight(
      merchantKey: merchantKey ?? this.merchantKey,
      merchantName: merchantName ?? this.merchantName,
      totalPaise: totalPaise ?? this.totalPaise,
      visits: visits ?? this.visits,
      avgPaise: avgPaise ?? this.avgPaise,
      topCategory: topCategory ?? this.topCategory,
    );
  }

  @override
  String toString() => 'MerchantInsight($merchantKey, visits: $visits)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MerchantInsight &&
          other.merchantKey == merchantKey &&
          other.merchantName == merchantName &&
          other.totalPaise == totalPaise &&
          other.visits == visits &&
          other.avgPaise == avgPaise &&
          other.topCategory == topCategory;

  @override
  int get hashCode => Object.hash(
        merchantKey,
        merchantName,
        totalPaise,
        visits,
        avgPaise,
        topCategory,
      );
}
