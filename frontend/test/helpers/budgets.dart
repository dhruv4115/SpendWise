/// One `GET /budgets` item, as the server sends it: `spentPaise` is the whole
/// month's spend in that category, whichever day of it the limit was set on.
Map<String, Object?> budgetWire({
  required String category,
  required int limitPaise,
  String month = '2026-09',
  int spentPaise = 0,
}) {
  return {
    'category': category,
    'month': month,
    'limitPaise': limitPaise,
    'spentPaise': spentPaise,
  };
}

/// A `GET /budgets` body.
Map<String, Object?> budgetsWire([
  List<Map<String, Object?>> items = const [],
]) {
  return {'items': items};
}
