import 'dart:async' as async;
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../services/app_exception.dart';
import '../../../services/auth_token_provider.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_token.dart';

/// The real [AuthRepository] — talks to Keycloak's own token endpoint
/// directly via `package:http`, not [ApiHttpClient]: that class always
/// JSON-encodes its request body and always targets the onboarding-
/// platform backend's own base URL, neither of which fits here.
/// Keycloak's token endpoint wants `application/x-www-form-urlencoded`
/// (the OAuth2 token-endpoint spec, not this app's own JSON convention),
/// and lives at a genuinely different base URL (the Keycloak server, not
/// onboarding-platform). Reusing `ApiHttpClient` would mean forcing a
/// second protocol shape through a class built for one, for no benefit —
/// its retry/backoff and status-code mapping don't transfer cleanly
/// either (Keycloak's own error shape for bad credentials is a 400 with
/// `error: invalid_grant`, not this app's `{"message": ...}` convention).
///
/// Grant type confirmed by reading the real realm export directly
/// (`tests/integration/shared/keycloak-realm-export.json` in the backend
/// repo — parsed with a throwaway script, not assumed from prose):
/// `onboarding-platform` is a `publicClient` (no client secret) with
/// `directAccessGrantsEnabled: true` and `standardFlowEnabled: false` —
/// the resource-owner-password-credentials (ROPC, `grant_type=password`)
/// grant is the only interactive one actually enabled, matching what an
/// internal agent app (username+password entered directly, no browser
/// redirect) needs and ruling out Authorization Code + PKCE, which this
/// realm doesn't support for this client at all.
///
/// Implements both [AuthRepository] and [AuthTokenProvider] on the same
/// class — investigated rather than defaulted (see NOTES.md's Phase 1):
/// a separate small `lib/services/`-owned adapter satisfying
/// [AuthTokenProvider] would need to import this class to construct one,
/// which `tool/check_layer_boundaries.sh`'s Check 2 forbids
/// (`lib/services/` may never import `lib/features/`). Implementing both
/// interfaces here instead means the *single* real token cache lives in
/// one place, and `main.dart` hands the same instance to both
/// `ApiClientImpl` (as an `AuthTokenProvider`) and wherever the app reads
/// login state (as an `AuthRepository`) — no duplication, no boundary
/// violation, since `lib/features/auth/data/` importing
/// `lib/services/auth_token_provider.dart` is the *allowed* direction.
class KeycloakAuthRepositoryImpl implements AuthRepository, AuthTokenProvider {
  final String keycloakBaseUrl;
  final String realm;
  final String clientId;
  final http.Client _client;
  final FlutterSecureStorage _storage;

  KeycloakAuthRepositoryImpl({
    required this.keycloakBaseUrl,
    this.realm = 'onboarding',
    this.clientId = 'onboarding-platform',
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'auth.accessToken';
  static const _refreshTokenKey = 'auth.refreshToken';
  static const _expiresAtKey = 'auth.expiresAt';

  AuthToken? _cached;

  Uri get _tokenUri => Uri.parse('$keycloakBaseUrl/realms/$realm/protocol/openid-connect/token');

  @override
  String? currentToken() => _cached?.accessToken;

  @override
  AuthToken? currentSession() => _cached;

  @override
  Future<void> initialize() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    final expiresAtRaw = await _storage.read(key: _expiresAtKey);
    if (accessToken == null || refreshToken == null || expiresAtRaw == null) return;
    _cached = AuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.parse(expiresAtRaw),
    );
  }

  @override
  Future<AuthToken> login({required String username, required String password}) async {
    final token = await _requestToken({
      'grant_type': 'password',
      'client_id': clientId,
      'username': username,
      'password': password,
    });
    await _persist(token);
    return token;
  }

  @override
  Future<AuthToken> refresh() async {
    final current = _cached;
    if (current == null) {
      // A precondition violation, not a network outcome — the same
      // reasoning ApiClientImpl.submitCase's null-caseId guard uses:
      // nothing should ever call refresh() without having logged in
      // first, so this is a caller-contract bug, not a real Keycloak
      // failure mode to render in the UI.
      throw StateError('AuthRepository.refresh() called with no prior login to refresh.');
    }
    final token = await _requestToken({
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': current.refreshToken,
    });
    await _persist(token);
    return token;
  }

  @override
  Future<void> logout() async {
    _cached = null;
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiresAtKey);
  }

  Future<void> _persist(AuthToken token) async {
    _cached = token;
    await _storage.write(key: _accessTokenKey, value: token.accessToken);
    await _storage.write(key: _refreshTokenKey, value: token.refreshToken);
    await _storage.write(key: _expiresAtKey, value: token.expiresAt.toIso8601String());
  }

  /// Maps Keycloak's own response shapes onto this app's shared
  /// [AppException] taxonomy — the same vocabulary every other network
  /// call in this app uses, so a `LoginScreen` can render a failure via
  /// the existing shared `AppErrorView` with no special-casing.
  Future<AuthToken> _requestToken(Map<String, String> form) async {
    http.Response response;
    try {
      response = await _client
          .post(
            _tokenUri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: form,
          )
          .timeout(const Duration(seconds: 10));
    } on async.TimeoutException {
      throw const AppTimeoutException();
    } on http.ClientException {
      throw const NetworkException();
    }

    final status = response.statusCode;
    if (status == 400 || status == 401) {
      // Keycloak's own OAuth2 error shape for bad credentials or an
      // invalid/expired refresh token is a 400 with
      // {"error": "invalid_grant", "error_description": "..."} — not a
      // 401, unlike this app's own backend. Mapped onto
      // UnauthorizedException regardless: from this app's perspective,
      // both mean the same thing ("these credentials don't get you in"),
      // and UnauthorizedException's isRetryable: false and AppErrorView
      // rendering already fit a login failure correctly.
      throw UnauthorizedException(_extractKeycloakError(response) ?? 'Incorrect username or password.');
    }
    if (status >= 500) {
      throw ServerException(status, _extractKeycloakError(response));
    }
    if (status >= 400) {
      throw ClientException(status, _extractKeycloakError(response));
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const ParseException();
      final accessToken = decoded['access_token'] as String?;
      final refreshToken = decoded['refresh_token'] as String?;
      final expiresIn = decoded['expires_in'] as int?;
      if (accessToken == null || refreshToken == null || expiresIn == null) {
        throw const ParseException();
      }
      return AuthToken(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      );
    } on FormatException {
      throw const ParseException();
    }
  }

  String? _extractKeycloakError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error_description'] is String) {
        return decoded['error_description'] as String;
      }
      if (decoded is Map && decoded['error'] is String) return decoded['error'] as String;
    } on FormatException {
      // Body wasn't JSON — no message to extract.
    }
    return null;
  }
}
