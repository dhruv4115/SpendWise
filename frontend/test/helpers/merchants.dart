import 'package:spendwise/features/merchants/domain/merchant_insight.dart';

/// One merchant's month, as the domain holds it.
///
/// The key is derived from the name, and the average from the total and the
/// visits, so a row is consistent with itself unless a test deliberately
/// makes it otherwise.
MerchantInsight merchant({
  required String merchantName,
  String? merchantKey,
  int totalPaise = 450000,
  int visits = 3,
  int? avgPaise,
  String topCategory = 'food',
}) {
  return MerchantInsight(
    merchantKey: merchantKey ?? merchantName.toLowerCase(),
    merchantName: merchantName,
    totalPaise: totalPaise,
    visits: visits,
    avgPaise: avgPaise ?? (visits == 0 ? 0 : (totalPaise / visits).round()),
    topCategory: topCategory,
  );
}

/// The same row as `GET /merchants` sends it.
Map<String, Object?> merchantWire({
  required String merchantName,
  String? merchantKey,
  int totalPaise = 450000,
  int visits = 3,
  int? avgPaise,
  String topCategory = 'food',
}) {
  return merchant(
    merchantName: merchantName,
    merchantKey: merchantKey,
    totalPaise: totalPaise,
    visits: visits,
    avgPaise: avgPaise,
    topCategory: topCategory,
  ).toJson();
}

/// A `GET /merchants` body.
Map<String, Object?> merchantsWire([
  List<Map<String, Object?>> items = const [],
]) {
  return {'items': items};
}
