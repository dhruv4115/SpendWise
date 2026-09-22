import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/errors/bank_error.dart';
import 'package:spendwise/core/network/error_mapper.dart';

const String _traceId = '9f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f';

Object envelope(
  String code,
  String message, {
  Map<String, String> details = const {},
  String traceId = _traceId,
}) {
  return {
    'error': {
      'code': code,
      'message': message,
      'details': details,
      'traceId': traceId,
    },
  };
}

DioException badResponse(
  int status, {
  Object? body,
  String path = '/transactions',
}) {
  final options = RequestOptions(path: path);
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: options,
      statusCode: status,
      data: body,
    ),
  );
}

void main() {
  group('status codes', () {
    test('400 becomes a ValidationError', () {
      final error = mapDioException(
        badResponse(
          400,
          body: envelope('VALIDATION_FAILED', 'That month is not valid.',
              details: {
                'month': 'Use the YYYY-MM format.',
              }),
        ),
      );

      expect(error, isA<ValidationError>());
      expect(error.statusCode, 400);
      expect(
        (error as ValidationError).fieldErrors,
        {'month': 'Use the YYYY-MM format.'},
      );
      expect(error.isRetryable, isFalse);
    });

    test('401 becomes an UnauthorisedError', () {
      final error = mapDioException(
        badResponse(401,
            body: envelope('AUTH_TOKEN_INVALID', 'Session ended.')),
      );

      expect(error, isA<UnauthorisedError>());
      expect(error.code, 'AUTH_TOKEN_INVALID');
      expect(error.statusCode, 401);
      expect(error.isRetryable, isFalse);
    });

    test('403 becomes a ForbiddenError', () {
      final error = mapDioException(
        badResponse(403, body: envelope('FORBIDDEN', 'Not allowed.')),
      );

      expect(error, isA<ForbiddenError>());
      expect(error.statusCode, 403);
    });

    test('404 becomes a NotFoundError', () {
      final error = mapDioException(
        badResponse(
          404,
          body: envelope('TRANSACTION_NOT_FOUND', 'We could not find that.'),
        ),
      );

      expect(error, isA<NotFoundError>());
      expect(error.code, 'TRANSACTION_NOT_FOUND');
      expect(error.userMessage, 'We could not find that.');
    });

    test('409 becomes a ConflictError', () {
      final error = mapDioException(
        badResponse(409, body: envelope('IDEMPOTENCY_CONFLICT', 'Key reused.')),
      );

      expect(error, isA<ConflictError>());
      expect(error.statusCode, 409);
      expect(error.isRetryable, isFalse);
    });

    test('422 becomes a ValidationError carrying every field', () {
      final error = mapDioException(
        badResponse(
          422,
          body: envelope('VALIDATION_FAILED', 'We could not save that budget.',
              details: {
                'limitPaise': 'A budget cannot be negative.',
                'month': 'Use the YYYY-MM format.',
              }),
        ),
      ) as ValidationError;

      expect(error.statusCode, 422);
      expect(error.fieldErrors, hasLength(2));
      expect(error.fieldErrors['limitPaise'], 'A budget cannot be negative.');
    });

    test('429 becomes a RateLimitedError that is not immediately retryable',
        () {
      final error = mapDioException(
        badResponse(429, body: envelope('RATE_LIMITED', 'Slow down.')),
      );

      expect(error, isA<RateLimitedError>());
      expect(error.isRetryable, isFalse);
    });

    test('500 becomes a retryable ServerError', () {
      final error = mapDioException(
        badResponse(500, body: envelope('INTERNAL_ERROR', 'Server trouble.')),
      );

      expect(error, isA<ServerError>());
      expect(error.statusCode, 500);
      expect(error.isRetryable, isTrue);
    });

    test('503 becomes a retryable ServerError', () {
      final error = mapDioException(
        badResponse(
          503,
          body: envelope('UPSTREAM_UNAVAILABLE', 'The bank is unavailable.'),
        ),
      );

      expect(error, isA<ServerError>());
      expect(error.statusCode, 503);
      expect(error.isRetryable, isTrue);
    });

    test('an unmapped status becomes an UnknownError', () {
      final error = mapDioException(badResponse(418));

      expect(error, isA<UnknownError>());
      expect(error.statusCode, 418);
      expect(error.userMessage, 'Something went wrong. Please try again.');
    });
  });

  group('bodies that are not the envelope', () {
    test('an HTML error page does not throw and yields a friendly message', () {
      final error = mapDioException(
        badResponse(
          502,
          body: '<html><head><title>502 Bad Gateway</title></head>'
              '<body><h1>502 Bad Gateway</h1></body></html>',
        ),
      );

      expect(error, isA<ServerError>());
      expect(error.message, isNull);
      expect(error.userMessage, contains('trouble'));
      expect(error.userMessage, isNot(contains('<')));
      expect(error.userMessage, isNot(contains('502')));
    });

    test('an empty body does not throw', () {
      expect(mapDioException(badResponse(500)), isA<ServerError>());
      expect(mapDioException(badResponse(500, body: '')), isA<ServerError>());
    });

    test('a JSON string body is still parsed', () {
      final error = mapDioException(
        badResponse(
          404,
          body: '{"error":{"code":"NOT_FOUND","message":"Nothing here.",'
              '"details":{},"traceId":"$_traceId"}}',
        ),
      );

      expect(error, isA<NotFoundError>());
      expect(error.userMessage, 'Nothing here.');
      expect(error.traceId, _traceId);
    });

    test('a body that is neither map nor string does not throw', () {
      expect(mapDioException(badResponse(500, body: [1, 2, 3])),
          isA<ServerError>());
    });
  });

  group('failures without a response', () {
    test('a connection timeout becomes a retryable NetworkError', () {
      final options = RequestOptions(path: '/transactions');
      final error = mapDioException(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      );

      expect(error, isA<NetworkError>());
      expect(error.code, 'CONNECT_TIMEOUT');
      expect(error.statusCode, isNull);
      expect(error.isRetryable, isTrue);
      expect(error.userMessage, contains('could not reach'));
    });

    test('a receive timeout and a dropped connection are NetworkErrors', () {
      final options = RequestOptions(path: '/summary');

      for (final type in [
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.badCertificate,
      ]) {
        final error = mapDioException(
          DioException(requestOptions: options, type: type),
        );
        expect(error, isA<NetworkError>(), reason: '$type');
        expect(error.isRetryable, isTrue, reason: '$type');
      }
    });

    test('a socket failure reported as unknown is a NetworkError', () {
      final options = RequestOptions(path: '/summary');
      final error = mapDioException(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const SocketException('Failed host lookup'),
        ),
      );

      expect(error, isA<NetworkError>());
      expect(error.isRetryable, isTrue);
    });

    test('a cancelled request is an UnknownError, not a failure to show', () {
      final options = RequestOptions(path: '/summary');
      final error = mapDioException(
        DioException(requestOptions: options, type: DioExceptionType.cancel),
      );

      expect(error, isA<UnknownError>());
      expect(error.code, 'REQUEST_CANCELLED');
      expect(error.isRetryable, isFalse);
    });
  });

  group('traceId', () {
    test('is captured from the envelope', () {
      final error = mapDioException(
        badResponse(500, body: envelope('INTERNAL_ERROR', 'Server trouble.')),
      );

      expect(error.traceId, _traceId);
    });

    test('is null when the body carries none', () {
      expect(mapDioException(badResponse(500, body: {'oops': true})).traceId,
          isNull);
      expect(mapDioException(badResponse(502, body: '<html></html>')).traceId,
          isNull);
    });
  });

  group('userMessage', () {
    test('prefers the server wording', () {
      final error = mapDioException(
        badResponse(409, body: envelope('CONFLICT', 'That budget moved on.')),
      );

      expect(error.userMessage, 'That budget moved on.');
    });

    test('falls back when the server sends markup, a code or a dump', () {
      const unusable = [
        '<p>nope</p>',
        'VALIDATION_FAILED',
        'Exception: bad state\n#0 main',
      ];

      for (final message in unusable) {
        final error = mapDioException(
          badResponse(404, body: {
            'error': {'code': 'NOT_FOUND', 'message': message},
          }),
        );
        expect(error.userMessage, 'We could not find that.', reason: message);
      }
    });

    test('falls back when the server message is an essay', () {
      final error = mapDioException(
        badResponse(404, body: {
          'error': {'code': 'NOT_FOUND', 'message': 'x' * 200},
        }),
      );

      expect(error.userMessage, 'We could not find that.');
    });
  });
}
