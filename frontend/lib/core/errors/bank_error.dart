import 'package:flutter/foundation.dart';

/// The only error type a repository is allowed to throw.
///
/// A `DioException` never escapes `core/network`: it is converted at the
/// repository border into one of these. Widgets render [userMessage] and
/// nothing else — [message] is whatever the server sent and may be missing,
/// stale or unusable, while [userMessage] is always safe to put on screen.
@immutable
sealed class BankError implements Exception {
  const BankError({this.message, required this.code, this.traceId});

  /// The server's human-readable message, when it sent one.
  final String? message;

  /// Machine-readable code from the error envelope, e.g. `VALIDATION_FAILED`.
  /// Never shown to a user.
  final String code;

  /// Correlation id from the error envelope. Safe to show in a "report this"
  /// affordance; it identifies a request, not a customer.
  final String? traceId;

  /// HTTP status, absent when the request never reached the server. Subtypes
  /// tied to one status pin it here; the open-ended ones take it as a field.
  int? get statusCode => null;

  /// Whether retrying the identical request could plausibly succeed.
  ///
  /// Only connectivity failures and server faults qualify. A 409 or a 422 will
  /// fail again unless the request itself changes, and a 429 needs a delay
  /// rather than an immediate retry.
  bool get isRetryable => false;

  /// Shown when the server said nothing useful.
  String get fallbackMessage;

  /// What a widget renders. Prefers the server's wording, falls back to a
  /// friendly default, and never leaks markup, stack traces or raw codes.
  String get userMessage => _presentable(message) ?? fallbackMessage;

  @override
  String toString() =>
      '$runtimeType(code: $code, status: $statusCode, traceId: $traceId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is BankError &&
          other.message == message &&
          other.code == code &&
          other.traceId == traceId &&
          other.statusCode == statusCode;

  @override
  int get hashCode =>
      Object.hash(runtimeType, message, code, traceId, statusCode);
}

/// Rejects anything that would look wrong, leak internals or wrap badly in a
/// snackbar: markup, multi-line dumps, bare codes and essays.
String? _presentable(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  if (text.length > 160) return null;
  if (text.contains('<') || text.contains('>')) return null;
  if (text.contains('\n') || text.contains('\t')) return null;
  if (RegExp(r'^[A-Z0-9_]+$').hasMatch(text)) return null;
  if (text.contains('Exception') || text.contains('#0 ')) return null;
  return text;
}

/// No usable connection: the request timed out, DNS failed, or the socket
/// dropped. The request may never have reached the bank.
final class NetworkError extends BankError {
  const NetworkError({
    super.message,
    super.code = 'NETWORK_UNAVAILABLE',
    super.traceId,
  });

  @override
  bool get isRetryable => true;

  @override
  String get fallbackMessage =>
      'We could not reach your bank. Check your connection and try again.';
}

/// 401 — the session is gone or was never valid.
final class UnauthorisedError extends BankError {
  const UnauthorisedError({
    super.message,
    super.code = 'AUTH_TOKEN_INVALID',
    super.traceId,
  });

  @override
  int? get statusCode => 401;

  @override
  String get fallbackMessage => 'Your session has ended. Please sign in again.';
}

/// 403 — signed in, but not allowed to do this.
final class ForbiddenError extends BankError {
  const ForbiddenError({
    super.message,
    super.code = 'FORBIDDEN',
    super.traceId,
  });

  @override
  int? get statusCode => 403;

  @override
  String get fallbackMessage =>
      'You do not have access to this. Contact support if that seems wrong.';
}

/// 404 — the thing being asked for is not there.
final class NotFoundError extends BankError {
  const NotFoundError({
    super.message,
    super.code = 'NOT_FOUND',
    super.traceId,
  });

  @override
  int? get statusCode => 404;

  @override
  String get fallbackMessage => 'We could not find that.';
}

/// 400 or 422 — the request was understood but is not acceptable.
///
/// [fieldErrors] maps a form field name to the reason it was rejected, so a
/// form can show the message under the offending field instead of in a banner.
final class ValidationError extends BankError {
  const ValidationError({
    super.message,
    super.code = 'VALIDATION_FAILED',
    super.traceId,
    this.statusCode,
    this.fieldErrors = const {},
  });

  @override
  final int? statusCode;

  final Map<String, String> fieldErrors;

  @override
  String get fallbackMessage => 'Please check the details and try again.';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidationError &&
          super == other &&
          _sameFields(other.fieldErrors, fieldErrors);

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        Object.hashAllUnordered(
          fieldErrors.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );
}

bool _sameFields(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// 409 — usually an idempotency key reused with a different body.
final class ConflictError extends BankError {
  const ConflictError({
    super.message,
    super.code = 'CONFLICT',
    super.traceId,
  });

  @override
  int? get statusCode => 409;

  @override
  String get fallbackMessage =>
      'That change clashed with another one. Reload and try again.';
}

/// 429 — too many requests.
final class RateLimitedError extends BankError {
  const RateLimitedError({
    super.message,
    super.code = 'RATE_LIMITED',
    super.traceId,
  });

  @override
  int? get statusCode => 429;

  @override
  String get fallbackMessage =>
      'Too many requests just now. Wait a moment and try again.';
}

/// 5xx — the bank is having trouble.
final class ServerError extends BankError {
  const ServerError({
    super.message,
    super.code = 'UPSTREAM_UNAVAILABLE',
    super.traceId,
    this.statusCode,
  });

  @override
  final int? statusCode;

  @override
  bool get isRetryable => true;

  @override
  String get fallbackMessage =>
      'Your bank is having trouble right now. Please try again shortly.';
}

/// Anything that does not fit: an unmapped status, a cancelled request, or a
/// failure that never became a response.
final class UnknownError extends BankError {
  const UnknownError({
    super.message,
    super.code = 'UNKNOWN',
    super.traceId,
    this.statusCode,
  });

  @override
  final int? statusCode;

  @override
  String get fallbackMessage => 'Something went wrong. Please try again.';
}
