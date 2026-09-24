import 'package:flutter/foundation.dart';

import '../../../core/utils/json_read.dart';
import 'transaction.dart';

/// Distinguishes "leave the cursor alone" from "clear it" in [copyWith].
const Object _unset = Object();

/// One page of `GET /transactions`.
@immutable
class TransactionPage {
  const TransactionPage({required this.items, this.nextCursor});

  /// Throws [FormatException] when the envelope or any transaction in it is
  /// malformed. One bad row fails the page: a feed that silently drops a row
  /// shows a customer a statement that does not add up.
  factory TransactionPage.fromJson(Map<String, dynamic> json) {
    return TransactionPage(
      items: List.unmodifiable(
        readObjectList(json, 'items', Transaction.fromJson),
      ),
      nextCursor: readStringOrNull(json, 'nextCursor'),
    );
  }

  /// Newest first, as the server sorts them. Unmodifiable.
  final List<Transaction> items;

  /// Opaque token for the page after this one; null on the last page.
  ///
  /// It encodes a transaction id, so it is never logged or printed.
  final String? nextCursor;

  bool get isLast => nextCursor == null;

  /// Back onto the wire's shape, for the offline cache. The cursor goes with
  /// it: a saved page that could not ask for the next one would strand a
  /// customer at row 50.
  Map<String, Object?> toJson() => {
        'items': [for (final txn in items) txn.toJson()],
        'nextCursor': nextCursor,
      };

  TransactionPage copyWith({
    List<Transaction>? items,
    Object? nextCursor = _unset,
  }) {
    return TransactionPage(
      items: items ?? this.items,
      nextCursor: identical(nextCursor, _unset)
          ? this.nextCursor
          : nextCursor as String?,
    );
  }

  /// No cursor: see [nextCursor].
  @override
  String toString() =>
      'TransactionPage(items: ${items.length}, isLast: $isLast)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionPage &&
          other.nextCursor == nextCursor &&
          listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(Object.hashAll(items), nextCursor);
}
