import 'package:flutter/foundation.dart';

import '../../../core/utils/json_read.dart';

final RegExp _hexColour = RegExp(r'^#?[0-9a-fA-F]{6}$');

/// A spending category, as the server defines it.
///
/// [icon] and [color] are names and hex, not Flutter types: the model stays
/// free of `dart:ui` so it can be parsed, cached and aggregated anywhere,
/// including inside an isolate. Presentation resolves them.
@immutable
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    final colour = readString(json, 'color');
    if (!_hexColour.hasMatch(colour)) {
      throw FormatException('Field "color" is not a #RRGGBB colour', colour);
    }
    return Category(
      id: readString(json, 'id'),
      name: readString(json, 'name'),
      icon: readString(json, 'icon'),
      color: colour,
    );
  }

  /// The stable identifier used everywhere else: `food`, `transport`.
  final String id;

  /// What the customer reads: `Food & Dining`.
  final String name;

  /// A Material icon name, e.g. `restaurant`.
  final String icon;

  /// `#RRGGBB`.
  final String color;

  /// The colour as opaque ARGB, so presentation can build a `Color` without
  /// re-parsing the hex or handling a malformed value a second time.
  int get argb =>
      0xFF000000 | int.parse(color.replaceFirst('#', ''), radix: 16);

  Category copyWith({
    String? id,
    String? name,
    String? icon,
    String? color,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
    );
  }

  @override
  String toString() => 'Category($id)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category &&
          other.id == id &&
          other.name == name &&
          other.icon == icon &&
          other.color == color;

  @override
  int get hashCode => Object.hash(id, name, icon, color);
}

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
