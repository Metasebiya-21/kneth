import 'package:sdui_demo/features/auth/domain/auth_repository.dart';
import 'package:sdui_demo/features/auth/domain/auth_token.dart';

/// A plain, in-memory fake — no secure storage, no network — for
/// exercising [AuthNotifier]/`LoginScreen` without a real
/// `BackendAuthRepositoryImpl`. Mirrors `FakeFlowRepository`/
/// `FakeApiClient`'s existing shape in this same directory.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.loginError, AuthToken? initialSession}) : _session = initialSession;

  AuthToken? _session;
  Object? loginError;
  int loginCallCount = 0;
  int refreshCallCount = 0;
  int logoutCallCount = 0;
  int initializeCallCount = 0;

  String? lastUsername;
  String? lastPassword;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
  }

  @override
  Future<AuthToken> login({required String username, required String password}) async {
    loginCallCount++;
    lastUsername = username;
    lastPassword = password;
    final error = loginError;
    if (error != null) throw error;
    _session = AuthToken(
      accessToken: 'fake-access-token',
      refreshToken: 'fake-refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    return _session!;
  }

  @override
  Future<AuthToken> refresh() async {
    refreshCallCount++;
    final current = _session;
    if (current == null) {
      throw StateError('refresh() called with no prior login');
    }
    _session = AuthToken(
      accessToken: 'refreshed-access-token',
      refreshToken: current.refreshToken,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    return _session!;
  }

  @override
  Future<void> logout() async {
    logoutCallCount++;
    _session = null;
  }

  @override
  AuthToken? currentSession() => _session;

  // Password flows: each records its call and throws its configured error,
  // if any. Scripted per test.
  Object? changePasswordError;
  Object? sendCodeError;
  Object? resendCodeError;
  Object? resetPasswordError;
  final List<String> calls = [];
  final List<Map<String, String>> changePasswordCalls = [];
  final List<Map<String, String>> resetPasswordCalls = [];

  @override
  Future<void> changePassword({
    required String username,
    required String currentPassword,
    required String newPassword,
  }) async {
    calls.add('changePassword');
    changePasswordCalls.add({'username': username, 'current': currentPassword, 'new': newPassword});
    final error = changePasswordError;
    if (error != null) throw error;
  }

  @override
  Future<void> sendPasswordResetCode({required String username}) async {
    calls.add('sendCode:$username');
    final error = sendCodeError;
    if (error != null) throw error;
  }

  @override
  Future<void> resendPasswordResetCode({required String username}) async {
    calls.add('resendCode:$username');
    final error = resendCodeError;
    if (error != null) throw error;
  }

  @override
  Future<void> resetPassword({required String username, required String code, required String newPassword}) async {
    calls.add('resetPassword');
    resetPasswordCalls.add({'username': username, 'code': code, 'new': newPassword});
    final error = resetPasswordError;
    if (error != null) throw error;
  }
}
