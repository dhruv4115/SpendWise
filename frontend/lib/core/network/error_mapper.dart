import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../errors/bank_error.dart';

/// The server's error envelope, once it has been prised out of a response body
/// that may not be JSON at all.
///
///     { "error": { "code", "message", "details": {}, "traceId" } }
@immutable
class ErrorEnvelope {
  const ErrorEnvelope({
    this.code,
    this.message,
    this.traceId,
    this.fieldErrors = const {},
  });

  static const ErrorEnvelope empty = ErrorEnvelope();

  final String? code;
  final String? message;
  final String? traceId;
  final Map<String, String> fieldErrors;
}

/// Converts a Dio failure into the single error type repositories may throw.
///
/// This is the only bridge between the transport library and the rest of the
/// app; nothing above `core/network` ever sees a [DioException].
BankError mapDioException(DioException error) {
  final response = error.response;
  final status = response?.statusCode;
  final envelope = parseErrorEnvelope(response?.data);

  _logInDebug(error, status, envelope);

  return switch (error.type) {
    DioExceptionType.connectionTimeout => NetworkError(
        message: envelope.message,
        code: 'CONNECT_TIMEOUT',
        traceId: envelope.traceId,
      ),
    DioExceptionType.sendTimeout => NetworkError(
        message: envelope.message,
        code: 'SEND_TIMEOUT',
        traceId: envelope.traceId,
      ),
    DioExceptionType.receiveTimeout => NetworkError(
        message: envelope.message,
        code: 'RECEIVE_TIMEOUT',
        traceId: envelope.traceId,
      ),
    // Dio gave up decoding a response that was still arriving.
    DioExceptionType.transformTimeout => NetworkError(
        message: envelope.message,
        code: 'TRANSFORM_TIMEOUT',
        traceId: envelope.traceId,
      ),
    DioExceptionType.connectionError => NetworkError(
        message: envelope.message,
        traceId: envelope.traceId,
      ),
    DioExceptionType.badCertificate => NetworkError(
        message: envelope.message,
        code: 'BAD_CERTIFICATE',
        traceId: envelope.traceId,
      ),
    DioExceptionType.cancel => UnknownError(
        message: envelope.message,
        code: 'REQUEST_CANCELLED',
        traceId: envelope.traceId,
      ),
    DioExceptionType.badResponse => _fromStatus(status, envelope),
    DioExceptionType.unknown => error.error is SocketException
        ? NetworkError(message: envelope.message, traceId: envelope.traceId)
        : _fromStatus(status, envelope),
  };
}

BankError _fromStatus(int? status, ErrorEnvelope envelope) {
  final code = envelope.code;
  final message = envelope.message;
  final traceId = envelope.traceId;

  return switch (status) {
    400 || 422 => ValidationError(
        message: message,
        code: code ?? 'VALIDATION_FAILED',
        traceId: traceId,
        statusCode: status,
        fieldErrors: envelope.fieldErrors,
      ),
    401 => UnauthorisedError(
        message: message,
        code: code ?? 'AUTH_TOKEN_INVALID',
        traceId: traceId,
      ),
    403 => ForbiddenError(
        message: message,
        code: code ?? 'FORBIDDEN',
        traceId: traceId,
      ),
    404 => NotFoundError(
        message: message,
        code: code ?? 'NOT_FOUND',
        traceId: traceId,
      ),
    409 => ConflictError(
        message: message,
        code: code ?? 'CONFLICT',
        traceId: traceId,
      ),
    429 => RateLimitedError(
        message: message,
        code: code ?? 'RATE_LIMITED',
        traceId: traceId,
      ),
    _ => switch (status) {
        final int s when s >= 500 => ServerError(
            message: message,
            code: code ?? 'UPSTREAM_UNAVAILABLE',
            traceId: traceId,
            statusCode: s,
          ),
        _ => UnknownError(
            message: message,
            code: code ?? 'UNKNOWN',
            traceId: traceId,
            statusCode: status,
          ),
      },
  };
}

/// Reads the error envelope out of a response body.
///
/// Tolerates every shape a failing server actually produces: a decoded map, a
/// JSON string, an HTML error page from a proxy, or nothing at all. Never
/// throws — a parser that throws inside error handling loses the real failure.
ErrorEnvelope parseErrorEnvelope(Object? data) {
  final decoded = _asMap(data);
  if (decoded == null) return ErrorEnvelope.empty;

  final Object? error = decoded['error'];
  final Map<Object?, Object?> body = error is Map ? error : decoded;

  final Object? details = body['details'];
  final fieldErrors = <String, String>{};
  if (details is Map) {
    for (final entry in details.entries) {
      final value = entry.value;
      if (value == null) continue;
      fieldErrors[entry.key.toString()] = value.toString();
    }
  }

  return ErrorEnvelope(
    code: _asString(body['code']),
    message: _asString(body['message']),
    traceId: _asString(body['traceId']),
    fieldErrors: fieldErrors,
  );
}

Map<Object?, Object?>? _asMap(Object? data) {
  if (data is Map) return data;
  if (data is String) {
    final text = data.trim();
    // An HTML error page from a proxy or load balancer, not an envelope.
    if (text.isEmpty || !text.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
  }
  return null;
}

String? _asString(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  return null;
}

/// Ids are redacted: a log line may say which endpoint failed, never which
/// customer or transaction it was for.
String redactPath(String path) => path
    .split('/')
    .map((segment) =>
        RegExp(r'^(txn|cat|mer|usr)_').hasMatch(segment) || segment.length > 16
            ? ':id'
            : segment)
    .join('/');

void _logInDebug(DioException error, int? status, ErrorEnvelope envelope) {
  if (!kDebugMode) return;
  final path = redactPath(error.requestOptions.path);
  debugPrint(
    '[${envelope.traceId ?? '-'}] ${envelope.code ?? error.type.name} '
    '${status ?? '-'} $path',
  );
}
