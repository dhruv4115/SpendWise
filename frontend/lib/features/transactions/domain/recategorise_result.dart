import 'package:flutter/foundation.dart';

import '../../../core/utils/json_read.dart';
import 'transaction.dart';

/// What `PATCH /transactions/{id}` reports back.
@immutable
class RecategoriseResult {
  const RecategoriseResult({
    required this.updated,
    required this.changedIds,
    required this.undoToken,
  });

  factory RecategoriseResult.fromJson(Map<String, dynamic> json) {
    return RecategoriseResult(
      updated: Transaction.fromJson(readObject(json, 'updated')),
      changedIds: readStringList(json, 'changedIds'),
      undoToken: readString(json, 'undoToken'),
    );
  }

  /// The transaction that was asked about, as the server now holds it.
  final Transaction updated;

  /// Every transaction the server actually moved, in any month — loaded on
  /// this device or not. A row that was already in the new category is not
  /// here, and is not touched by an undo either. Unmodifiable.
  final List<String> changedIds;

  /// Redeemable once at `POST /transactions/undo`. A credential for reversing
  /// the change, so it is never printed.
  final String undoToken;

  RecategoriseResult copyWith({
    Transaction? updated,
    List<String>? changedIds,
    String? undoToken,
  }) {
    return RecategoriseResult(
      updated: updated ?? this.updated,
      changedIds: changedIds ?? this.changedIds,
      undoToken: undoToken ?? this.undoToken,
    );
  }

  /// No ids and no token: see [undoToken].
  @override
  String toString() => 'RecategoriseResult(changed: ${changedIds.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecategoriseResult &&
          other.updated == updated &&
          other.undoToken == undoToken &&
          listEquals(other.changedIds, changedIds);

  @override
  int get hashCode =>
      Object.hash(updated, Object.hashAll(changedIds), undoToken);
}
