/// The server's seeded categories, as `GET /categories` sends them.
const List<Map<String, Object?>> seededCategories = [
  {
    'id': 'food',
    'name': 'Food & Dining',
    'icon': 'restaurant',
    'color': '#E8590C'
  },
  {
    'id': 'groceries',
    'name': 'Groceries',
    'icon': 'shopping_basket',
    'color': '#2F9E44'
  },
  {
    'id': 'transport',
    'name': 'Transport',
    'icon': 'directions_bus',
    'color': '#1C7ED6'
  },
  {
    'id': 'shopping',
    'name': 'Shopping',
    'icon': 'shopping_bag',
    'color': '#9C36B5'
  },
  {
    'id': 'bills',
    'name': 'Bills & Utilities',
    'icon': 'receipt_long',
    'color': '#F08C00'
  },
  {
    'id': 'entertainment',
    'name': 'Entertainment',
    'icon': 'movie',
    'color': '#D6336C'
  },
  {
    'id': 'health',
    'name': 'Health',
    'icon': 'medical_services',
    'color': '#0CA678'
  },
  {'id': 'travel', 'name': 'Travel', 'icon': 'flight', 'color': '#4C6EF5'},
  {
    'id': 'education',
    'name': 'Education',
    'icon': 'school',
    'color': '#5C7CFA'
  },
  {'id': 'other', 'name': 'Other', 'icon': 'category', 'color': '#868E96'},
];

/// A `GET /categories` body.
Map<String, Object?> categoriesWire([
  List<Map<String, Object?>> items = seededCategories,
]) {
  return {'items': items};
}
