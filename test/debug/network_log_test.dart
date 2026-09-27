// The debug network log's capture and redaction. Redaction happens BEFORE
// anything is stored, so these assert on what the log holds, not on what a
// screen shows.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sdui_demo/debug/network_log.dart';
import 'package:sdui_demo/services/api_http_client.dart';
import 'package:sdui_demo/services/app_exception.dart';

String _everything(NetworkLogEntry e) => [
      e.url,
      e.requestHeaders.toString(),
      e.requestBody,
      e.responseHeaders.toString(),
      e.responseBody,
    ].join('\n');

void main() {
  group('redaction', () {
    test('JSON: password/token/otp/secret values are replaced at any depth; everything else is kept', () {
      final out = redactJsonText(jsonEncode({
        'username': 'agent-7',
        'password': 'p1',
        'current_password': 'p2',
        'new_password': 'p3',
        'otp': '123456',
        'nested': {
          'access_token': 'a',
          'refresh_token': 'r',
          'client_secret': 's',
          'list': [
            {'token': 't', 'ok': 1},
          ],
        },
        'expires_in': 300,
      }))!;
      for (final secret in ['"p1"', '"p2"', '"p3"', '"123456"', '"a"', '"r"', '"s"', '"t"']) {
        expect(out, isNot(contains(secret)));
      }
      expect(out, contains('"agent-7"'));
      expect(out, contains('300'));
      expect(out, contains('"ok": 1'));
      expect(RegExp(redactedValue).allMatches(out).length, 8);
    });

    test('FastAPI 422: the echoed `input` (the rejected password) is redacted, loc/msg kept', () {
      final out = redactJsonText(jsonEncode({
        'detail': [
          {'loc': ['body', 'new_password'], 'msg': 'String should have at least 8 characters', 'input': 'hunter2'},
        ],
      }))!;
      expect(out, isNot(contains('hunter2')));
      expect(out, contains('String should have at least 8 characters'));
    });

    test('headers: Authorization and Cookie are redacted, others kept', () {
      expect(redactHeaders({'Authorization': 'Bearer abc', 'cookie': 'x', 'content-type': 'application/json'}), {
        'Authorization': redactedValue,
        'cookie': redactedValue,
        'content-type': 'application/json',
      });
    });

    test('query parameters and form bodies are redacted by key', () {
      expect(redactUrl(Uri.parse('https://h.test/p?token=abc&page=2')), isNot(contains('abc')));
      expect(redactUrl(Uri.parse('https://h.test/p?token=abc&page=2')), contains('page=2'));
      expect(
        redactFormText('grant_type=password&username=u&password=p').split('&'),
        ['grant_type=password', 'username=u', 'password=$redactedValue'],
      );
    });

    test('bodies that cannot be redacted by key (plain text, binary) are summarized, never stored', () {
      expect(describeBody(utf8.encode('password is hunter2'), 'text/plain'), isNot(contains('hunter2')));
      expect(describeBody([0xff, 0xfe, 0x00], 'application/octet-stream'), contains('not captured'));
      expect(describeBody([], 'application/json'), isNull);
    });
  });

  group('NetworkLogClient under ApiHttpClient', () {
    test('records method, redacted URL, status, timing and redacted bodies — and the caller still gets the body',
        () async {
      final log = NetworkLog();
      final api = ApiHttpClient(
        baseUrl: 'https://backend.test',
        client: NetworkLogClient(
          MockClient((_) async => http.Response(
                jsonEncode({'access_token': 'eyJ-secret', 'expires_in': 300, 'refresh_token': 'r-secret'}),
                200,
                headers: {'content-type': 'application/json'},
              )),
          log,
        ),
      );

      final body = await api.request(
        method: 'POST',
        path: '/auth/login',
        body: {'username': 'agent-7', 'password': 'Temp-123'},
        headers: {'Authorization': 'Bearer old-token'},
      );
      expect(body['access_token'], 'eyJ-secret', reason: 'logging must not alter what the app receives');

      final entry = log.entries.single;
      expect(entry.method, 'POST');
      expect(entry.url, 'https://backend.test/auth/login');
      expect(entry.statusCode, 200);
      expect(entry.duration, isNotNull);
      final captured = _everything(entry);
      for (final secret in ['Temp-123', 'eyJ-secret', 'r-secret', 'old-token']) {
        expect(captured, isNot(contains(secret)), reason: '$secret leaked into the log');
      }
      expect(captured, contains('agent-7'));
    });

    test('a transport failure is recorded as an error entry and still reaches the caller as before', () async {
      final log = NetworkLog();
      final api = ApiHttpClient(
        baseUrl: 'https://backend.test',
        maxAttempts: 1,
        client: NetworkLogClient(MockClient((_) async => throw http.ClientException('refused')), log),
      );
      await expectLater(api.request(method: 'GET', path: '/x'), throwsA(isA<NetworkException>()));
      expect(log.entries.single.error, isNotNull);
      expect(log.entries.single.statusCode, isNull);
    });

    test('newest first, capped at maxEntries', () async {
      final log = NetworkLog(maxEntries: 3);
      final client = NetworkLogClient(MockClient((r) async => http.Response('{}', 200)), log);
      for (var i = 1; i <= 5; i++) {
        await client.get(Uri.parse('https://h.test/$i'));
      }
      expect(log.entries.map((e) => e.url), ['https://h.test/5', 'https://h.test/4', 'https://h.test/3']);
    });
  });
}
