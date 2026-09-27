// Contract tests for BackendAuthRepositoryImpl — package:http's MockClient,
// the same methodology api_client_impl_test.dart and the Keycloak client's
// tests (which this replaces) used. Response bodies are the backend's real
// shapes, read from onboarding-platform's source (shared/auth/router.py,
// schemas.py, http_errors.py) and checked live with curl — including
// FastAPI's own 422 `detail` shape, which echoes the rejected password in
// `input`. The live counterpart is test/live/auth_proxy_live_test.dart.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sdui_demo/features/auth/data/backend_auth_repository_impl.dart';
import 'package:sdui_demo/features/auth/domain/password_change_required.dart';
import 'package:sdui_demo/services/app_exception.dart';

class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> values = {};

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    values[key] = value;
  }

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => values[key];

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    values.remove(key);
  }

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      values.containsKey(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => values.clear();

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => Map.of(values);
}

late _FakeSecureStoragePlatform _storage;
final List<http.Request> _requests = [];

BackendAuthRepositoryImpl _repositoryWith(Future<http.Response> Function(http.Request) handler) {
  _storage = _FakeSecureStoragePlatform();
  FlutterSecureStoragePlatform.instance = _storage;
  _requests.clear();
  return BackendAuthRepositoryImpl(
    baseUrl: 'https://backend.test',
    client: MockClient((request) {
      _requests.add(request);
      return handler(request);
    }),
    storage: const FlutterSecureStorage(),
  );
}

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

http.Response _message(String message, int status) => _json({'message': message}, status);

Map<String, dynamic> _tokenBody({String access = 'access-1', String? refresh = 'refresh-1', int expiresIn = 300}) => {
      'access_token': access,
      'expires_in': expiresIn,
      'refresh_token': refresh,
      'token_type': 'Bearer',
    };

/// A repository already logged in (refresh token [refresh]), whose next
/// requests get [then], in order.
Future<BackendAuthRepositoryImpl> _loggedIn({String refresh = 'refresh-1', List<http.Response> then = const []}) async {
  final script = [_json(_tokenBody(refresh: refresh), 200), ...then];
  final repository = _repositoryWith((_) async => script.removeAt(0));
  await repository.login(username: 'agent1', password: 'secret');
  _requests.clear();
  return repository;
}

void main() {
  group('login', () {
    test('POSTs JSON {username, password} to /auth/login', () async {
      final repository = _repositoryWith((_) async => _json(_tokenBody(), 200));
      final token = await repository.login(username: 'agent1', password: 'secret');

      final request = _requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://backend.test/auth/login');
      expect(request.headers['content-type'], contains('application/json'));
      expect(jsonDecode(request.body), {'username': 'agent1', 'password': 'secret'});
      expect(token.accessToken, 'access-1');
      expect(token.refreshToken, 'refresh-1');
      expect(token.expiresAt.difference(DateTime.now()).inSeconds, closeTo(300, 5));
      expect(repository.currentToken(), 'access-1');
    });

    test('persists the session under the same keys as before the swap, readable by a fresh instance', () async {
      final repository = _repositoryWith((_) async => _json(_tokenBody(), 200));
      await repository.login(username: 'agent1', password: 'secret');
      expect(_storage.values.keys, containsAll(['auth.accessToken', 'auth.refreshToken', 'auth.expiresAt']));

      final fresh = BackendAuthRepositoryImpl(
        baseUrl: 'https://backend.test',
        client: MockClient((_) async => fail('initialize must not touch the network')),
        storage: const FlutterSecureStorage(),
      );
      expect(fresh.currentSession(), isNull);
      await fresh.initialize();
      expect(fresh.currentToken(), 'access-1');
      expect(fresh.currentSession()!.refreshToken, 'refresh-1');
    });

    test('401 (wrong credentials) is UnauthorizedException with the backend\'s message, not retried', () async {
      final repository = _repositoryWith((_) async => _message('Invalid username or password', 401));
      await expectLater(
        repository.login(username: 'agent1', password: 'wrong'),
        throwsA(isA<UnauthorizedException>().having((e) => e.message, 'message', 'Invalid username or password')),
      );
      expect(_requests, hasLength(1));
      expect(repository.currentSession(), isNull);
    });

    test('the backend\'s exact first-login 403 becomes PasswordChangeRequiredException, carrying the username',
        () async {
      final repository = _repositoryWith(
        (_) async => _message('your temporary password must be changed before you can sign in', 403),
      );
      await expectLater(
        repository.login(username: 'agent-7', password: 'Temp-123'),
        throwsA(isA<PasswordChangeRequiredException>().having((e) => e.username, 'username', 'agent-7')),
      );
      expect(repository.currentSession(), isNull);
      expect(_storage.values, isEmpty);
    });

    test('the pinned 403 text is exactly the backend\'s (a reword upstream must fail this test first)', () {
      // Copied character-for-character from onboarding-platform's
      // app/shared/auth/keycloak_token_client.py (PasswordChangeRequiredError).
      expect(passwordChangeRequiredMessage, 'your temporary password must be changed before you can sign in');
      expect(isPasswordChangeRequiredMessage('  Your temporary password must be changed before you can sign in '),
          isTrue);
      expect(isPasswordChangeRequiredMessage('your temporary password must be changed'), isFalse);
    });

    test('any OTHER 403 stays an ordinary ForbiddenException (no guessing from partial text)', () async {
      final repository = _repositoryWith((_) async => _message('account disabled', 403));
      await expectLater(
        repository.login(username: 'agent1', password: 'secret'),
        throwsA(isA<ForbiddenException>().having((e) => e.message, 'message', 'account disabled')),
      );
    });

    test('502 (Keycloak down behind the proxy) is ServerException, and is NOT retried', () async {
      final repository = _repositoryWith((_) async => _message('authentication service unavailable', 502));
      await expectLater(repository.login(username: 'a', password: 'b'), throwsA(isA<ServerException>()));
      expect(_requests, hasLength(1), reason: 'auth calls are single-attempt; see the class doc comment');
    });

    test('a login response without a refresh token is a ParseException (the refresh loop needs one)', () async {
      final repository = _repositoryWith((_) async => _json(_tokenBody(refresh: null), 200));
      await expectLater(repository.login(username: 'a', password: 'b'), throwsA(isA<ParseException>()));
      expect(repository.currentSession(), isNull);
    });

    test('a transport failure is NetworkException', () async {
      final repository = _repositoryWith((_) async => throw http.ClientException('connection refused'));
      await expectLater(repository.login(username: 'a', password: 'b'), throwsA(isA<NetworkException>()));
    });
  });

  group('refresh', () {
    test('POSTs {refresh_token} to /auth/refresh and persists the new pair', () async {
      final repository = await _loggedIn(refresh: 'refresh-1', then: [_json(_tokenBody(access: 'access-2', refresh: 'refresh-2'), 200)]);

      final token = await repository.refresh();
      expect(_requests.single.url.path, '/auth/refresh');
      expect(jsonDecode(_requests.single.body), {'refresh_token': 'refresh-1'});
      expect(token.accessToken, 'access-2');
      expect(_storage.values['auth.refreshToken'], 'refresh-2');
    });

    test('a refresh response without refresh_token keeps the previous one', () async {
      final repository = await _loggedIn(refresh: 'refresh-1', then: [_json(_tokenBody(access: 'access-2', refresh: null), 200)]);
      final token = await repository.refresh();
      expect(token.refreshToken, 'refresh-1');
    });

    test('401 (expired refresh token) is UnauthorizedException', () async {
      final repository = await _loggedIn(then: [_message('Invalid or expired refresh token', 401)]);
      await expectLater(repository.refresh(), throwsA(isA<UnauthorizedException>()));
    });

    test('with no prior login throws StateError locally, with no HTTP call', () async {
      final repository = _repositoryWith((_) async => fail('no request expected'));
      await expectLater(repository.refresh(), throwsStateError);
      expect(_requests, isEmpty);
    });
  });

  group('logout', () {
    test('clears memory and storage, then POSTs {refresh_token} to /auth/logout (an empty 204)', () async {
      final repository = await _loggedIn(refresh: 'refresh-1', then: [http.Response('', 204)]);

      await repository.logout();
      expect(repository.currentSession(), isNull);
      expect(_storage.values, isEmpty);
      expect(_requests.single.url.path, '/auth/logout');
      expect(jsonDecode(_requests.single.body), {'refresh_token': 'refresh-1'});
    });

    test('a failing server logout is swallowed; the local session is gone regardless', () async {
      for (final failure in [_message('Invalid or expired refresh token', 401), _message('down', 502)]) {
        final repository = await _loggedIn(then: [failure]);
        await repository.logout();
        expect(repository.currentSession(), isNull);
        expect(_storage.values, isEmpty);
      }
    });

    test('with no session makes no HTTP call', () async {
      final repository = _repositoryWith((_) async => fail('no request expected'));
      await repository.logout();
      expect(_requests, isEmpty);
    });
  });

  group('password change', () {
    test('POSTs {username, current_password, new_password} to /auth/password/change', () async {
      final repository = _repositoryWith((_) async => _message('Password changed', 200));
      await repository.changePassword(username: 'agent-7', currentPassword: 'Temp-123', newPassword: 'New-pass-99');
      expect(_requests.single.url.path, '/auth/password/change');
      expect(jsonDecode(_requests.single.body), {
        'username': 'agent-7',
        'current_password': 'Temp-123',
        'new_password': 'New-pass-99',
      });
      expect(repository.currentSession(), isNull, reason: 'a change persists nothing; login follows');
    });

    test('401 wrong current password, 422 weak/unchanged, 429 rate-limited each keep their status', () async {
      final cases = <http.Response, Matcher>{
        _message('Invalid username or password', 401): isA<UnauthorizedException>(),
        _message('The new password must be different from the current one.', 422):
            isA<ClientException>().having((e) => e.statusCode, 'status', 422),
        _message('Too many attempts. Please try again later.', 429): isA<ClientException>()
            .having((e) => e.statusCode, 'status', 429)
            .having((e) => e.message, 'message', 'Too many attempts. Please try again later.'),
      };
      for (final entry in cases.entries) {
        final repository = _repositoryWith((_) async => entry.key);
        await expectLater(
          repository.changePassword(username: 'u', currentPassword: 'c', newPassword: 'n-12345678'),
          throwsA(entry.value),
        );
        expect(_requests, hasLength(1), reason: 'never retried — every attempt counts against the limit');
      }
    });

    test('FastAPI\'s own 422 is summarized from loc/msg, never from the echoed `input` (the password)', () async {
      final repository = _repositoryWith((_) async => _json({
            'detail': [
              {
                'type': 'string_too_short',
                'loc': ['body', 'new_password'],
                'msg': 'String should have at least 8 characters',
                'input': 'short',
                'ctx': {'min_length': 8},
              },
            ],
          }, 422));
      await expectLater(
        repository.changePassword(username: 'u', currentPassword: 'c', newPassword: 'short'),
        throwsA(isA<ClientException>()
            .having((e) => e.message, 'message', 'new_password: String should have at least 8 characters')
            .having((e) => e.message, 'message', isNot(contains('short\'')))),
      );
    });
  });

  group('password reset', () {
    test('send and resend POST {username} to /auth/otp/send and /auth/otp/resend', () async {
      const generic = 'If the account exists, an OTP has been sent to its registered phone.';
      final repository = _repositoryWith((_) async => _message(generic, 200));
      await repository.sendPasswordResetCode(username: 'agent-7');
      await repository.resendPasswordResetCode(username: 'agent-7');
      expect(_requests.map((r) => r.url.path), ['/auth/otp/send', '/auth/otp/resend']);
      expect(_requests.map((r) => jsonDecode(r.body)), everyElement({'username': 'agent-7'}));
    });

    test('the per-IP 429 on send is ClientException(429), not retried', () async {
      final repository = _repositoryWith((_) async => _message('Too many OTP requests. Please try again later.', 429));
      await expectLater(
        repository.sendPasswordResetCode(username: 'u'),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 429)),
      );
      expect(_requests, hasLength(1), reason: 'a retried send is a second SMS');
    });

    test('an SMS-gateway failure (502) is ServerException, not retried', () async {
      final repository = _repositoryWith((_) async => _message('Failed to send SMS.', 502));
      await expectLater(repository.sendPasswordResetCode(username: 'u'), throwsA(isA<ServerException>()));
      expect(_requests, hasLength(1));
    });

    test('reset POSTs {username, otp, new_password} to /auth/password/reset', () async {
      final repository = _repositoryWith((_) async => _message('Password successfully reset', 200));
      await repository.resetPassword(username: 'agent-7', code: '123456', newPassword: 'New-pass-99');
      expect(_requests.single.url.path, '/auth/password/reset');
      expect(jsonDecode(_requests.single.body), {'username': 'agent-7', 'otp': '123456', 'new_password': 'New-pass-99'});
    });

    test('reset: wrong/expired code 422 and too-many-attempts 429 stay distinct', () async {
      var repository = _repositoryWith((_) async => _message('Invalid or expired OTP.', 422));
      await expectLater(
        repository.resetPassword(username: 'u', code: '000000', newPassword: 'New-pass-99'),
        throwsA(isA<ClientException>()
            .having((e) => e.statusCode, 'status', 422)
            .having((e) => e.message, 'message', 'Invalid or expired OTP.')),
      );
      repository = _repositoryWith((_) async => _message('Too many attempts. Request a new OTP.', 429));
      await expectLater(
        repository.resetPassword(username: 'u', code: '000000', newPassword: 'New-pass-99'),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 429)),
      );
    });
  });
}
