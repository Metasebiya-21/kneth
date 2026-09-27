// Mocks at the transport level (package:http's own MockClient), not by
// faking ApiHttpClient itself — this is what actually exercises its
// request-building, retry/backoff, and failure-mapping logic for real.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sdui_demo/services/api_http_client.dart';
import 'package:sdui_demo/services/app_exception.dart';

ApiHttpClient _clientWith(http.Client mock, {int maxAttempts = 3, Duration? timeout}) {
  return ApiHttpClient(
    baseUrl: 'https://example.test',
    client: mock,
    maxAttempts: maxAttempts,
    // Real, but tiny, so retry tests don't sit through real backoff delays.
    baseBackoff: const Duration(milliseconds: 1),
    timeout: timeout ?? const Duration(seconds: 5),
  );
}

void main() {
  test('a successful response returns parsed JSON', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/things');
      return http.Response(jsonEncode({'ok': true}), 200);
    });

    final result = await _clientWith(mock).request(method: 'GET', path: '/things');

    expect(result, {'ok': true});
  });

  test('query params and a POST body are sent as expected', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.queryParameters, {'a': '1'});
      expect(jsonDecode(request.body), {'name': 'Ada'});
      return http.Response(jsonEncode({'id': 1}), 200);
    });

    final result = await _clientWith(mock).request(
      method: 'POST',
      path: '/things',
      queryParams: {'a': '1'},
      body: {'name': 'Ada'},
    );

    expect(result, {'id': 1});
  });

  test('401 maps to UnauthorizedException and is not retried', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return http.Response('{}', 401);
    });

    await expectLater(
      _clientWith(mock).request(method: 'GET', path: '/things'),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(calls, 1);
  });

  test('403 maps to ForbiddenException and is not retried', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return http.Response(jsonEncode({'message': "not your client"}), 403);
    });

    await expectLater(
      _clientWith(mock).request(method: 'GET', path: '/things'),
      throwsA(isA<ForbiddenException>()),
    );
    expect(calls, 1);
  });

  test('a 4xx status maps to ClientException carrying the status code and is not retried', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return http.Response(jsonEncode({'message': 'bad field'}), 422);
    });

    try {
      await _clientWith(mock).request(method: 'GET', path: '/things');
      fail('expected a ClientException');
    } on ClientException catch (e) {
      expect(e.statusCode, 422);
      expect(e.message, 'bad field');
    }
    expect(calls, 1);
  });

  test('a 5xx status maps to ServerException and is retried up to maxAttempts', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return http.Response('{}', 503);
    });

    await expectLater(
      _clientWith(mock, maxAttempts: 3).request(method: 'GET', path: '/things'),
      throwsA(isA<ServerException>()),
    );
    expect(calls, 3);
  });

  test('a retryable failure that succeeds on a later attempt returns the successful result', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      if (calls < 3) return http.Response('{}', 503);
      return http.Response(jsonEncode({'ok': true}), 200);
    });

    final result = await _clientWith(mock, maxAttempts: 5).request(method: 'GET', path: '/things');

    expect(result, {'ok': true});
    expect(calls, 3);
  });

  test('malformed JSON maps to ParseException', () async {
    final mock = MockClient((request) async {
      return http.Response('not json', 200);
    });

    await expectLater(
      _clientWith(mock).request(method: 'GET', path: '/things'),
      throwsA(isA<ParseException>()),
    );
  });

  test('a valid JSON response that is not an object maps to ParseException', () async {
    final mock = MockClient((request) async {
      return http.Response(jsonEncode([1, 2, 3]), 200);
    });

    await expectLater(
      _clientWith(mock).request(method: 'GET', path: '/things'),
      throwsA(isA<ParseException>()),
    );
  });

  test('a real transport failure maps to NetworkException', () async {
    final mock = MockClient((request) async {
      throw http.ClientException('connection refused');
    });

    await expectLater(
      _clientWith(mock).request(method: 'GET', path: '/things'),
      throwsA(isA<NetworkException>()),
    );
  });

  test('a response slower than the configured timeout maps to AppTimeoutException', () async {
    final mock = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return http.Response('{}', 200);
    });

    await expectLater(
      _clientWith(mock, timeout: const Duration(milliseconds: 20)).request(method: 'GET', path: '/things'),
      throwsA(isA<AppTimeoutException>()),
    );
  });

  group('requestList (bare-JSON-array responses, e.g. GET /clients)', () {
    test('a successful response returns the parsed JSON array', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/clients');
        return http.Response(
          jsonEncode([
            {'id': '1', 'name': 'Awash Bank'},
          ]),
          200,
        );
      });

      final result = await _clientWith(mock).requestList(method: 'GET', path: '/clients');

      expect(result, [
        {'id': '1', 'name': 'Awash Bank'},
      ]);
    });

    test('a JSON object response maps to ParseException, not silently accepted', () async {
      final mock = MockClient((request) async {
        return http.Response(jsonEncode({'not': 'a list'}), 200);
      });

      await expectLater(
        _clientWith(mock).requestList(method: 'GET', path: '/clients'),
        throwsA(isA<ParseException>()),
      );
    });

    test('status-code mapping (e.g. 403) applies the same as request()', () async {
      final mock = MockClient((request) async => http.Response('{}', 403));

      await expectLater(
        _clientWith(mock).requestList(method: 'GET', path: '/clients'),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });

  group('backend auth-route shapes (added with the /auth proxy)', () {
    test('an empty 2xx body (POST /auth/logout is a 204) is an empty map, not a ParseException', () async {
      final client = _clientWith(MockClient((_) async => http.Response('', 204)));
      expect(await client.request(method: 'POST', path: '/auth/logout', body: {'refresh_token': 'r'}), isEmpty);
    });

    test('FastAPI\'s {"detail": [...]} 422 becomes "field: msg", never exposing the echoed input', () async {
      final client = _clientWith(MockClient((_) async => http.Response(
            jsonEncode({
              'detail': [
                {'loc': ['body', 'new_password'], 'msg': 'String should have at least 8 characters', 'input': 'hunter2'},
              ],
            }),
            422,
          )));
      await expectLater(
        client.request(method: 'POST', path: '/x'),
        throwsA(isA<ClientException>()
            .having((e) => e.message, 'message', 'new_password: String should have at least 8 characters')
            .having((e) => e.message, 'message', isNot(contains('hunter2')))),
      );
    });

    test('a {"message": ...} body still wins over detail, and a plain-string detail is used as-is', () async {
      var client = _clientWith(MockClient((_) async => http.Response(jsonEncode({'detail': 'Not Found'}), 404)));
      await expectLater(
        client.request(method: 'GET', path: '/x'),
        throwsA(isA<ClientException>().having((e) => e.message, 'message', 'Not Found')),
      );
      client = _clientWith(MockClient(
        (_) async => http.Response(jsonEncode({'message': 'bad field', 'detail': 'ignored'}), 422),
      ));
      await expectLater(
        client.request(method: 'GET', path: '/x'),
        throwsA(isA<ClientException>().having((e) => e.message, 'message', 'bad field')),
      );
    });
  });
}
