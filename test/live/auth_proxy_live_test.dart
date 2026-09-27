// LIVE: BackendAuthRepositoryImpl against a RUNNING onboarding-platform
// (:8000, which proxies the dev Keycloak). Skips itself if the backend isn't
// reachable. See NOTES.md, "Auth through the backend's /auth proxy", for
// exactly which legs this covers and which it can't (the SMS leg).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sdui_demo/features/auth/data/backend_auth_repository_impl.dart';
import 'package:sdui_demo/features/auth/domain/password_change_required.dart';
import 'package:sdui_demo/features/auth/presentation/auth_notifier.dart';
import 'package:sdui_demo/services/app_exception.dart';

const _backend = 'http://127.0.0.1:8000';
const _agentUsername = 'tagent';
const _agentPassword = 'test#123';
// tool/seed_dev_platform_admin.sh's identity; hires the throwaway agent.
const _adminUsername = 'dev-platform-admin';
const _adminPassword = 'dev-platform-admin-password-123';
const _clientId = 'e8ce7cac-22fb-4858-8328-bd62297c7e75';
const _regionId = 'ee826f67-fcb1-4eb9-9b80-0938b17de5ea';

class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _v = {};
  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async => _v[key] = value;
  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => _v[key];
  @override
  Future<void> delete({required String key, required Map<String, String> options}) async => _v.remove(key);
  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async => _v.containsKey(key);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async => _v.clear();
  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => Map.of(_v);
}

BackendAuthRepositoryImpl _freshRepository() {
  FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
  return BackendAuthRepositoryImpl(baseUrl: _backend);
}

/// Whether the backend accepts [token] as a real caller.
Future<int> _clientsStatus(String token) async =>
    (await http.get(Uri.parse('$_backend/clients'), headers: {'Authorization': 'Bearer $token'})).statusCode;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool reachable;

  setUpAll(() async {
    HttpOverrides.global = null;
    try {
      reachable = (await http.get(Uri.parse('$_backend/docs')).timeout(const Duration(seconds: 5))).statusCode == 200;
    } catch (_) {
      reachable = false;
    }
    if (!reachable) {
      // ignore: avoid_print
      print('SKIPPED: $_backend is not reachable — live-only test.');
    }
  });

  test('login -> token accepted -> refresh -> new token accepted -> logout revokes the refresh token', () async {
    if (!reachable) return;
    final auth = _freshRepository();

    final first = await auth.login(username: _agentUsername, password: _agentPassword);
    expect(await _clientsStatus(first.accessToken), 200);

    final refreshed = await auth.refresh();
    expect(refreshed.accessToken, isNot(first.accessToken));
    expect(await _clientsStatus(refreshed.accessToken), 200);

    final refreshToken = auth.currentSession()!.refreshToken;
    await auth.logout();
    expect(auth.currentSession(), isNull);
    // The server-side session really ended: the refresh token is dead.
    final reuse = await http.post(
      Uri.parse('$_backend/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    expect(reuse.statusCode, 401, reason: reuse.body);
  });

  test('a wrong password is UnauthorizedException with the backend\'s message', () async {
    if (!reachable) return;
    await expectLater(
      _freshRepository().login(username: _agentUsername, password: 'not-the-password'),
      throwsA(isA<UnauthorizedException>().having((e) => e.message, 'message', 'Invalid username or password')),
    );
  });

  test('forgot-password, unknown username: send and resend succeed exactly like a real account (no enumeration);'
      ' a reset with any code is the generic 422', () async {
    if (!reachable) return;
    final auth = _freshRepository();
    const nobody = 'no-such-agent-for-kneth-live-test';
    await auth.sendPasswordResetCode(username: nobody);
    await auth.resendPasswordResetCode(username: nobody);
    await expectLater(
      auth.resetPassword(username: nobody, code: '000000', newPassword: 'Whatever-123'),
      throwsA(isA<ClientException>()
          .having((e) => e.statusCode, 'status', 422)
          .having((e) => e.message, 'message', 'Invalid or expired OTP.')),
    );
  });

  test('first login, live: hire -> temp password is 403 (exact text matched) -> change -> signed in -> old password dead',
      () async {
    if (!reachable) return;
    final admin = _freshRepository();
    try {
      await admin.login(username: _adminUsername, password: _adminPassword);
    } on UnauthorizedException {
      // ignore: avoid_print
      print('SKIPPED (first-login leg): $_adminUsername could not sign in with the password '
          'tool/seed_dev_platform_admin.sh documents, so no agent can be hired. See NOTES.md.');
      return;
    }
    final adminHeaders = {'Authorization': 'Bearer ${admin.currentToken()}', 'Content-Type': 'application/json'};

    final suffix = Random.secure().nextInt(1 << 30);
    final hire = await http.post(
      Uri.parse('$_backend/identity/agents'),
      headers: adminHeaders,
      body: jsonEncode({
        'firstName': 'Kneth',
        'lastName': 'Live',
        'email': 'kneth-live-$suffix@example.com',
        'phone': '+2519${(suffix % 100000000).toString().padLeft(8, '0')}',
        'gender': 'female',
        'regionId': _regionId,
        'clientId': _clientId,
      }),
    );
    expect(hire.statusCode, 201, reason: hire.body);
    final agentId = jsonDecode(hire.body)['id'] as String;
    final temporary = jsonDecode(hire.body)['temporary_password'] as String;
    addTearDown(() async {
      // Best effort: revoke the assignment, then hard-delete the history-free agent.
      await http.delete(Uri.parse('$_backend/operations/agents/$agentId/clients/$_clientId/assignment'),
          headers: adminHeaders);
      await http.delete(Uri.parse('$_backend/identity/agents/$agentId'), headers: adminHeaders);
    });

    // Through AuthNotifier, the way the app does it.
    final auth = _freshRepository();
    final notifier = AuthNotifier(auth);
    addTearDown(notifier.dispose);

    // 1. The temporary password: the backend's REAL 403 text is recognised.
    await expectLater(
      auth.login(username: agentId, password: temporary),
      throwsA(isA<PasswordChangeRequiredException>()),
    );
    await notifier.login(username: agentId, password: temporary);
    expect(notifier.state, isA<AuthPasswordChangeRequired>());

    // 2. Wrong current password -> 401, still on the change step.
    await notifier.completePasswordChange(currentPassword: '${temporary}x', newPassword: 'Kneth-Chosen-77');
    expect((notifier.state as AuthPasswordChangeRequired).error, isA<UnauthorizedException>());

    // 3. Unchanged new password -> 422, still on the change step.
    await notifier.completePasswordChange(currentPassword: temporary, newPassword: temporary);
    final unchanged = (notifier.state as AuthPasswordChangeRequired).error;
    expect(unchanged, isA<ClientException>().having((e) => e.statusCode, 'status', 422));

    // 4. The real change, then automatic sign-in with the new password.
    await notifier.completePasswordChange(currentPassword: temporary, newPassword: 'Kneth-Chosen-77');
    expect(notifier.state, isA<AuthLoggedIn>());
    expect(await _clientsStatus(auth.currentToken()!), anyOf(200, 403),
        reason: 'the token is accepted as a real caller (403 only if this client scope is not visible to it)');

    // 5. The temporary password is dead; the new one is the password now.
    await expectLater(
      _freshRepository().login(username: agentId, password: temporary),
      throwsA(isA<UnauthorizedException>()),
    );
    await _freshRepository().login(username: agentId, password: 'Kneth-Chosen-77');
  });
}
