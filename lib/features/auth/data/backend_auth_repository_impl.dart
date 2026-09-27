import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../services/api_http_client.dart';
import '../../../services/app_exception.dart';
import '../../../services/auth_token_provider.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_token.dart';
import '../domain/password_change_required.dart';

/// The exact text of the backend's 403 for "right password, but it's a
/// temporary one that must be changed first" (`KeycloakTokenClient._token`
/// in onboarding-platform, raising `PasswordChangeRequiredError`), compared
/// after trimming and lowercasing.
///
/// FRAGILE, on purpose and in the open: the backend identifies this 403 only
/// by its status and message text — it has no stable machine-readable code
/// (backend NOTES.md, Phase 25, names this gap itself). A 403 from
/// `/auth/login` with any OTHER text is treated as an ordinary failure. If
/// the backend rewords this sentence, first-login stops reaching the
/// change-password screen and the agent instead sees the 403's own message
/// on the login screen — degraded, not silent. A test pins this string; see
/// NOTES.md, "Auth through the backend's /auth proxy". Replace this with a
/// code check once the backend adds one.
const passwordChangeRequiredMessage = 'your temporary password must be changed before you can sign in';

bool isPasswordChangeRequiredMessage(String message) =>
    message.trim().toLowerCase() == passwordChangeRequiredMessage;

/// The real [AuthRepository], talking to the onboarding-platform backend's
/// own `/auth/*` routes (backend NOTES.md, Phases 23 and 25), which proxy
/// Keycloak's password grant server-side. Replaces the earlier direct-
/// Keycloak client: the app no longer needs Keycloak's URL, realm or client
/// id at all, and every auth call now speaks this backend's JSON and
/// `{"message": ...}` error convention — which is why it goes through
/// [ApiHttpClient], unlike its predecessor.
///
/// Its [ApiHttpClient] is built here with `maxAttempts: 1`, never shared
/// with `ApiClientImpl`'s retrying one: none of these calls is safe to
/// replay blindly. A retried `/auth/otp/send` sends a second SMS and burns
/// the account's hourly quota; a retried `/auth/password/change` or
/// `/auth/password/reset` counts against the backend's per-account attempt
/// limit. The caller decides whether to try again.
///
/// Implements both [AuthRepository] and [AuthTokenProvider] on one class,
/// for the same reason as before the swap (NOTES.md, Phase 1):
/// `lib/services/` may not import `lib/features/`, so the single token cache
/// has to live here and `main.dart` hands this same instance to both.
///
/// Uses the same secure-storage keys as the Keycloak client it replaced —
/// the tokens themselves are the same Keycloak tokens — so a session saved
/// before the swap survives it.
class BackendAuthRepositoryImpl implements AuthRepository, AuthTokenProvider {
  final ApiHttpClient _http;
  final FlutterSecureStorage _storage;

  BackendAuthRepositoryImpl({
    required String baseUrl,
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _http = ApiHttpClient(baseUrl: baseUrl, client: client, maxAttempts: 1),
        _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'auth.accessToken';
  static const _refreshTokenKey = 'auth.refreshToken';
  static const _expiresAtKey = 'auth.expiresAt';

  AuthToken? _cached;

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
    final Map<String, dynamic> body;
    try {
      body = await _post('/auth/login', {'username': username, 'password': password});
    } on ForbiddenException catch (e) {
      if (isPasswordChangeRequiredMessage(e.message)) {
        throw PasswordChangeRequiredException(username: username, message: e.message);
      }
      rethrow;
    }
    final token = _parseToken(body, previousRefreshToken: null);
    await _persist(token);
    return token;
  }

  @override
  Future<AuthToken> refresh() async {
    final current = _cached;
    if (current == null) {
      // A caller-contract bug, not a network outcome — nothing should call
      // refresh() without having logged in first.
      throw StateError('AuthRepository.refresh() called with no prior login to refresh.');
    }
    final body = await _post('/auth/refresh', {'refresh_token': current.refreshToken});
    final token = _parseToken(body, previousRefreshToken: current.refreshToken);
    await _persist(token);
    return token;
  }

  @override
  Future<void> logout() async {
    final refreshToken = _cached?.refreshToken;
    // Local first: the agent is signed out on this device the moment this
    // is called, however long (or whether) the server call below takes.
    _cached = null;
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiresAtKey);
    if (refreshToken == null) return;
    try {
      await _post('/auth/logout', {'refresh_token': refreshToken});
    } on AppException {
      // Best effort. An already-expired refresh token (401) or an
      // unreachable server leaves nothing for the agent to do about it.
    }
  }

  @override
  Future<void> changePassword({
    required String username,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _post('/auth/password/change', {
      'username': username,
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  @override
  Future<void> sendPasswordResetCode({required String username}) async {
    await _post('/auth/otp/send', {'username': username});
  }

  @override
  Future<void> resendPasswordResetCode({required String username}) async {
    await _post('/auth/otp/resend', {'username': username});
  }

  @override
  Future<void> resetPassword({required String username, required String code, required String newPassword}) async {
    await _post('/auth/password/reset', {'username': username, 'otp': code, 'new_password': newPassword});
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) =>
      _http.request(method: 'POST', path: path, body: body);

  Future<void> _persist(AuthToken token) async {
    _cached = token;
    await _storage.write(key: _accessTokenKey, value: token.accessToken);
    await _storage.write(key: _refreshTokenKey, value: token.refreshToken);
    await _storage.write(key: _expiresAtKey, value: token.expiresAt.toIso8601String());
  }

  /// The backend's `LoginResponse`: `access_token` and `expires_in` always,
  /// `refresh_token` optional in its schema. A login with no refresh token
  /// is unusable here (the background refresh loop needs one), so that's a
  /// [ParseException]; a refresh response without one keeps the previous
  /// refresh token, which is what an OAuth2 server omitting it means.
  AuthToken _parseToken(Map<String, dynamic> body, {required String? previousRefreshToken}) {
    final accessToken = body['access_token'];
    final expiresIn = body['expires_in'];
    final refreshToken = body['refresh_token'] ?? previousRefreshToken;
    if (accessToken is! String || expiresIn is! int || refreshToken is! String) {
      throw const ParseException();
    }
    return AuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }
}
