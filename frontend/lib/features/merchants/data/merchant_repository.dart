import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json_read.dart';
import '../domain/merchant_insight.dart';

/// Everything the app reads from `/merchants`. Throws [BankError] only.
class MerchantRepository {
  MerchantRepository({required Dio dio}) : _dio = dio;

  static const String merchantsPath = '/merchants';

  final Dio _dio;

  /// One row per merchant for [month] (`YYYY-MM`), biggest spend first.
  /// Unmodifiable.
  Future<List<MerchantInsight>> fetchMerchants(String month) {
    return _dio.getObject(
      merchantsPath,
      query: {'month': month},
      parse: (json) => List<MerchantInsight>.unmodifiable(
        readObjectList(json, 'items', MerchantInsight.fromJson),
      ),
      malformedCode: 'MALFORMED_MERCHANTS',
    );
  }
}

final Provider<MerchantRepository> merchantRepositoryProvider =
    Provider<MerchantRepository>(
  (ref) => MerchantRepository(dio: ref.watch(dioProvider)),
);
