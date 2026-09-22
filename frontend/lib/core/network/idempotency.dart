import 'dart:math';

/// Header every mutating call must carry, so a retry after a dropped response
/// replays the original outcome instead of charging twice.
const String idempotencyKeyHeader = 'Idempotency-Key';

final Random _secureRandom = Random.secure();

/// A fresh RFC 4122 version 4 UUID, from a cryptographically secure source.
///
/// Hand-rolled on purpose: one function is cheaper than a dependency, and the
/// project pins its package list.
String newIdempotencyKey() {
  final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));

  bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4.
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 10xx.

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Holds one idempotency key for the lifetime of a single user intent.
///
/// A confirmation screen creates this once and reads [key] on every attempt,
/// so pressing "Try again" after a timeout reuses the same key and the server
/// replays its stored response. [reset] is called only when the user starts a
/// genuinely new action — never on retry.
///
/// This is a controller-owned object, not a state value: a notifier keeps it
/// privately and exposes the key it hands out as part of its immutable state.
class IdempotencyKeyHolder {
  String? _key;

  /// Generated on first read and stable from then on.
  String get key => _key ??= newIdempotencyKey();

  /// Whether a key has been handed out yet.
  bool get hasKey => _key != null;

  /// Drops the current key so the next read starts a new attempt.
  void reset() => _key = null;
}
