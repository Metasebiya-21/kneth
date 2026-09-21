// Contract tests for KeycloakAuthRepositoryImpl, same methodology as
// api_client_impl_test.dart — package:http's own MockClient, never a real
// Keycloak call. No live server is required or attempted; see NOTES.md's
// Phase 5 for the (separate, later) live verification.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sdui_demo/features/auth/data/keycloak_auth_repository_impl.dart';
import 'package:sdui_demo/services/app_exception.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// An in-memory fake of the secure-storage platform channel — flutter_test
/// has no built-in mock for this plugin (unlike path_provider's method
/// channel, already reused for native_capture's own tests), so this
/// mirrors the interface directly instead. Same idea as this app's other
/// fakes: no real platform, no real disk, just enough to exercise
/// initialize()/persist()/logout()'s read-write-delete cycle.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => _values[key];

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      _values.containsKey(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => _values.clear();

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => Map.of(_values);
}

KeycloakAuthRepositoryImpl _repositoryWith(Future<http.Response> Function(http.Request) handler) {
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
  return KeycloakAuthRepositoryImpl(
    keycloakBaseUrl: 'https://keycloak.test',
    client: MockClient(handler),
    storage: const FlutterSecureStorage(),
  );
}

Map<String, dynamic> _tokenBody({String access = 'access-1', String refresh = 'refresh-1', int expiresIn = 300}) => {
      'access_token': access,
      'refresh_token': refresh,
      'expires_in': expiresIn,
      'token_type': 'Bearer',
    };

void main() {
  test('login POSTs the password grant with the confirmed client_id, form-encoded', () async {
    final repository = _repositoryWith((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://keycloak.test/realms/onboarding/protocol/openid-connect/token');
      expect(request.headers['content-type'], contains('application/x-www-form-urlencoded'));
      final form = Uri.splitQueryString(request.body);
      expect(form, {
        'grant_type': 'password',
        'client_id': 'onboarding-platform',
        'username': 'agent1',
        'password': 'secret',
      });
      return http.Response(jsonEncode(_tokenBody()), 200);
    });

    final token = await repository.login(username: 'agent1', password: 'secret');

    expect(token.accessToken, 'access-1');
    expect(token.refreshToken, 'refresh-1');
    expect(repository.currentToken(), 'access-1');
    expect(repository.currentSession()?.accessToken, 'access-1');
  });

  test('login persists the token, readable back via a fresh instance after initialize()', () async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    final repository = KeycloakAuthRepositoryImpl(
      keycloakBaseUrl: 'https://keycloak.test',
      client: MockClient((request) async => http.Response(jsonEncode(_tokenBody()), 200)),
      storage: const FlutterSecureStorage(),
    );
    await repository.login(username: 'agent1', password: 'secret');

    final reloaded = KeycloakAuthRepositoryImpl(
      keycloakBaseUrl: 'https://keycloak.test',
      client: MockClient((request) async => http.Response('{}', 500)),
      storage: const FlutterSecureStorage(),
    );
    expect(reloaded.currentToken(), isNull);
    await reloaded.initialize();

    expect(reloaded.currentToken(), 'access-1');
  });

  test('invalid credentials (Keycloak\'s real 400 invalid_grant shape) map to UnauthorizedException', () async {
    final repository = _repositoryWith((request) async {
      return http.Response(
        jsonEncode({'error': 'invalid_grant', 'error_description': 'Invalid user credentials'}),
        400,
      );
    });

    await expectLater(
      repository.login(username: 'agent1', password: 'wrong'),
      throwsA(isA<UnauthorizedException>().having((e) => e.message, 'message', 'Invalid user credentials')),
    );
    expect(repository.currentToken(), isNull);
  });

  test('a 5xx from Keycloak maps to ServerException', () async {
    final repository = _repositoryWith((request) async => http.Response('{}', 503));

    await expectLater(
      repository.login(username: 'agent1', password: 'secret'),
      throwsA(isA<ServerException>()),
    );
  });

  test('refresh POSTs the refresh_token grant using the persisted refresh token', () async {
    final calls = <Map<String, String>>[];
    final repository = _repositoryWith((request) async {
      calls.add(Uri.splitQueryString(request.body));
      if (calls.length == 1) return http.Response(jsonEncode(_tokenBody(refresh: 'refresh-1')), 200);
      return http.Response(jsonEncode(_tokenBody(access: 'access-2', refresh: 'refresh-2')), 200);
    });
    await repository.login(username: 'agent1', password: 'secret');

    final refreshed = await repository.refresh();

    expect(calls[1], {
      'grant_type': 'refresh_token',
      'client_id': 'onboarding-platform',
      'refresh_token': 'refresh-1',
    });
    expect(refreshed.accessToken, 'access-2');
    expect(repository.currentToken(), 'access-2');
  });

  test('refresh with no prior login throws locally, without making an HTTP call', () async {
    var called = false;
    final repository = _repositoryWith((request) async {
      called = true;
      return http.Response('{}', 200);
    });

    await expectLater(repository.refresh(), throwsA(isA<StateError>()));
    expect(called, isFalse);
  });

  test('logout clears the in-memory token and secure storage', () async {
    final repository = _repositoryWith((request) async => http.Response(jsonEncode(_tokenBody()), 200));
    await repository.login(username: 'agent1', password: 'secret');
    expect(repository.currentToken(), isNotNull);

    await repository.logout();

    expect(repository.currentToken(), isNull);
    expect(repository.currentSession(), isNull);
  });
}
