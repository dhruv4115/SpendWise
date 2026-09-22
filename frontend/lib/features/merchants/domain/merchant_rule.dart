import 'package:flutter/foundation.dart';

import '../../../core/utils/json_read.dart';

/// "Everything from this merchant is this category."
///
/// Created when a recategorisation is applied to a whole merchant rather than
/// to one line, and undone by the same token that undoes the transactions.
@immutable
class MerchantRule {
  const MerchantRule({required this.merchantKey, required this.category});

  factory MerchantRule.fromJson(Map<String, dynamic> json) {
    return MerchantRule(
      merchantKey: readString(json, 'merchantKey'),
      category: readString(json, 'category'),
    );
  }

  /// The normalised merchant key the rule applies to: `swiggy`.
  final String merchantKey;

  final String category;

  MerchantRule copyWith({String? merchantKey, String? category}) {
    return MerchantRule(
      merchantKey: merchantKey ?? this.merchantKey,
      category: category ?? this.category,
    );
  }

  @override
  String toString() => 'MerchantRule($merchantKey -> $category)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MerchantRule &&
          other.merchantKey == merchantKey &&
          other.category == category;

  @override
  int get hashCode => Object.hash(merchantKey, category);
}
