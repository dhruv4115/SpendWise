/// Every location in the app, in one place.
///
/// Screens navigate with these constants, never with a string literal: a typo
/// in a path is then a compile error rather than a 404 at runtime. Filters are
/// a sheet, not a route — they belong to a screen's state, not to its address.
abstract final class Routes {
  /// Shown while the keystore is being read on boot.
  static const String splashPath = '/splash';
  static const String splashName = 'splash';

  static const String loginPath = '/login';
  static const String loginName = 'login';

  /// The app, locked. Every route redirects here while the session is
  /// [SessionLocked], and the way out is the device's own authentication.
  static const String lockPath = '/lock';
  static const String lockName = 'lock';

  static const String overviewPath = '/overview';
  static const String overviewName = 'overview';

  static const String transactionsPath = '/transactions';
  static const String transactionsName = 'transactions';

  static const String transactionDetailPath = '/transactions/:id';
  static const String transactionDetailName = 'transactionDetail';

  static const String budgetsPath = '/budgets';
  static const String budgetsName = 'budgets';

  static const String budgetDetailPath = '/budgets/:category';
  static const String budgetDetailName = 'budgetDetail';

  static const String merchantsPath = '/merchants';
  static const String merchantsName = 'merchants';

  static const String merchantDetailPath = '/merchants/:id';
  static const String merchantDetailName = 'merchantDetail';

  /// Path parameter names, so a builder and its route cannot disagree.
  static const String idParam = 'id';
  static const String categoryParam = 'category';

  /// Carries the location a signed-out customer was trying to reach, so they
  /// land there after signing in instead of on a generic home screen.
  static const String fromQueryParam = 'from';

  /// Narrows the feed to one category id: `/transactions?category=food`.
  static const String categoryQueryParam = 'category';

  /// Sub-route segments, relative to their branch. go_router joins these onto
  /// the branch path to form [transactionDetailPath] and friends.
  static const String idSegment = ':$idParam';
  static const String categorySegment = ':$categoryParam';

  /// The feed narrowed to [category].
  static String transactionsInCategory(String category) => Uri(
        path: transactionsPath,
        queryParameters: {categoryQueryParam: category},
      ).toString();

  static String transactionDetail(String id) =>
      '$transactionsPath/${Uri.encodeComponent(id)}';

  static String budgetDetail(String category) =>
      '$budgetsPath/${Uri.encodeComponent(category)}';

  static String merchantDetail(String merchantKey) =>
      '$merchantsPath/${Uri.encodeComponent(merchantKey)}';
}
