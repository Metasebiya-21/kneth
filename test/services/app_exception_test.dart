import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/services/app_exception.dart';

void main() {
  test('transient/transport failures are retryable', () {
    expect(const NetworkException().isRetryable, isTrue);
    expect(const AppTimeoutException().isRetryable, isTrue);
    expect(const ServerException(503).isRetryable, isTrue);
  });

  test('failures where the request itself was the problem are not retryable', () {
    expect(const ClientException(422).isRetryable, isFalse);
    expect(const UnauthorizedException().isRetryable, isFalse);
    expect(const ForbiddenException().isRetryable, isFalse);
    expect(const ParseException().isRetryable, isFalse);
    expect(const UnknownException().isRetryable, isFalse);
  });

  test('ServerException/ClientException carry their status code', () {
    expect(const ServerException(503).statusCode, 503);
    expect(const ClientException(422).statusCode, 422);
  });

  test('every variant provides a non-empty human message by default', () {
    const exceptions = <AppException>[
      NetworkException(),
      AppTimeoutException(),
      ServerException(500),
      ClientException(400),
      UnauthorizedException(),
      ForbiddenException(),
      ParseException(),
      UnknownException(),
    ];
    for (final exception in exceptions) {
      expect(exception.message, isNotEmpty, reason: '${exception.runtimeType} has no message');
    }
  });
}
