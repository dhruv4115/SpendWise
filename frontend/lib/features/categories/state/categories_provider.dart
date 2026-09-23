import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../auth/state/session_provider.dart';
import '../data/category_repository.dart';
import '../domain/category.dart';

/// Every category, fetched once per signed-in customer and then kept.
///
/// Deliberately not auto-disposed: the list is small, identical on every
/// screen, and only changes when the server does, so the category sheet opens
/// instantly from the second time on. It is keyed to the customer rather than
/// to the app's lifetime — signing in as someone else fetches it afresh.
///
/// A failed fetch stays failed until something invalidates it, which is what
/// the sheet's Retry does.
final FutureProvider<List<Category>> categoriesProvider =
    FutureProvider<List<Category>>((ref) async {
  final customer = ref.watch(
    sessionProvider.select((state) => state.session?.user.id),
  );
  // Signed out there is nobody to fetch for, and asking would only earn a
  // 401 from whichever screen is still on its way out.
  if (customer == null) throw const UnauthorisedError();
  return ref.watch(categoryRepositoryProvider).fetchAll();
});

extension CategoryLookup on List<Category> {
  /// The category with [id], or null when the list does not have it — a
  /// category the server added after this list was fetched, say.
  Category? byId(String id) {
    for (final category in this) {
      if (category.id == id) return category;
    }
    return null;
  }

  /// What to call [id] on screen: the server's name for it, or the id itself
  /// with a capital letter while the list is missing or has not heard of it.
  String nameOf(String id) => byId(id)?.name ?? fallbackCategoryName(id);
}

/// `food` -> `Food`. Only for when the real name is not available.
String fallbackCategoryName(String id) =>
    id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}';
