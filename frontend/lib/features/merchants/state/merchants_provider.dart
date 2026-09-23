import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/merchant_repository.dart';
import '../domain/merchant_insight.dart';

/// One month's merchant roll-up, keyed by `YYYY-MM`.
///
/// Each row names its merchant's top category, so a recategorisation
/// invalidates this for the months it touched.
final AutoDisposeFutureProviderFamily<List<MerchantInsight>, String>
    merchantsProvider =
    FutureProvider.autoDispose.family<List<MerchantInsight>, String>(
  (ref, month) => ref.watch(merchantRepositoryProvider).fetchMerchants(month),
);
