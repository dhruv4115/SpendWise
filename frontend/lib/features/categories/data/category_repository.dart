import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json_read.dart';
import '../domain/category.dart';

/// Everything the app reads from `/categories`. Throws [BankError] only.
class CategoryRepository {
  CategoryRepository({required Dio dio}) : _dio = dio;

  static const String categoriesPath = '/categories';

  final Dio _dio;

  /// Every category the server knows, in the server's order. Unmodifiable.
  Future<List<Category>> fetchAll() {
    return _dio.getObject(
      categoriesPath,
      parse: (json) => List<Category>.unmodifiable(
        readObjectList(json, 'items', Category.fromJson),
      ),
      malformedCode: 'MALFORMED_CATEGORIES',
    );
  }
}

final Provider<CategoryRepository> categoryRepositoryProvider =
    Provider<CategoryRepository>(
  (ref) => CategoryRepository(dio: ref.watch(dioProvider)),
);
