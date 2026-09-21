import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../services/app_exception.dart';
import '../domain/auth_repository.dart';
import '../domain/token_refresh_policy.dart';

/// See main.dart for the override (a real `KeycloakAuthRepositoryImpl`).
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  throw UnimplementedError(
    'authRepositoryProvider has no default — it must be overridden, see main.dart.',
  );
});

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});

/// Same sealed-status idiom as `SyncStatus`/`FlowViewState`/
/// `DynamicFieldOptionsStatus`. Lives in presentation/, not domain/, for
/// the same reason `FlowViewState` does: this describes "is this app
/// session's login attempt in progress/failed right now," an artifact of
/// one session's async operation — not a fact about a business concept
/// (compare with `AuthToken`, in domain/, which *is* a fact: a real
/// session, however this screen currently feels about it).
sealed class AuthState {
  const AuthState();
}

/// Checking secure storage for a previously-persisted session — the very
/// first state, before [AuthNotifier.initialize] resolves.
class AuthCheckingStorage extends AuthState {
  const AuthCheckingStorage();
}

class AuthLoggedOut extends AuthState {
  const AuthLoggedOut();
}

class AuthLoggingIn extends AuthState {
  const AuthLoggingIn();
}

class AuthLoggedIn extends AuthState {
  const AuthLoggedIn();
}

class AuthFailed extends AuthState {
  final AppException error;
  const AuthFailed(this.error);
}

/// Owns the login/logout lifecycle and a background token-refresh loop —
/// see `token_refresh_policy.dart`'s own doc comment for why this exists
/// at all (keeping `AuthTokenProvider.currentToken()` synchronous, per
/// NOTES.md's Phase 1). Two triggers call [_maybeRefresh]: a periodic
/// timer (so a long-lived, foregrounded session still gets refreshed
/// before it actually expires) and app resume (so a session backgrounded
/// past its expiry is caught the moment the agent comes back, not left to
/// fail on the very next request). Both are best-effort: a failed
/// background refresh is swallowed here, not surfaced as an error state —
/// if the token is genuinely no longer valid, the very next real API call
/// will hit a real 401, which `ApiClientImpl`'s `onUnauthorized` callback
/// (wired in main.dart to [forceLogout]) already handles correctly.
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  Timer? _refreshTimer;
  AppLifecycleListener? _lifecycleListener;

  AuthNotifier(this._repository) : super(const AuthCheckingStorage());

  /// Call once, at app startup, before `runApp` — mirrors flow's own
  /// cheap-local-check-before-runApp shape (see NOTES.md).
  Future<void> initialize() async {
    await _repository.initialize();
    if (_repository.currentSession() != null) {
      state = const AuthLoggedIn();
      _startBackgroundRefresh();
    } else {
      state = const AuthLoggedOut();
    }
  }

  Future<void> login({required String username, required String password}) async {
    state = const AuthLoggingIn();
    try {
      await _repository.login(username: username, password: password);
    } on AppException catch (e) {
      state = AuthFailed(e);
      return;
    } catch (e) {
      state = AuthFailed(UnknownException(e.toString()));
      return;
    }
    // Deliberately outside the try/catch above: a real bug was caught
    // here during testing — starting background refresh failing (e.g.
    // AppLifecycleListener needs a live Flutter binding, unavailable in a
    // plain `test()`, only `testWidgets()`) was being caught by the same
    // clause and incorrectly reported as a *login* failure, even though
    // login itself had already genuinely succeeded. Login succeeding and
    // background-refresh infrastructure starting cleanly are two
    // unrelated concerns; only the former should ever produce AuthFailed.
    state = const AuthLoggedIn();
    _startBackgroundRefresh();
  }

  Future<void> logout() async {
    _stopBackgroundRefresh();
    await _repository.logout();
    state = const AuthLoggedOut();
  }

  /// What `ApiClientImpl.onUnauthorized` triggers (wired in main.dart) —
  /// a real 401 from an otherwise-present token. Synchronous from the
  /// caller's point of view (fires the state change immediately, so
  /// `SduiDemoApp`'s reactive swap back to `LoginScreen` happens right
  /// away); the repository's own `logout()` (secure-storage deletion) is
  /// still awaited underneath, just not blocking the state transition on
  /// it.
  void forceLogout() {
    _stopBackgroundRefresh();
    state = const AuthLoggedOut();
    unawaited(_repository.logout());
  }

  void _startBackgroundRefresh() {
    _stopBackgroundRefresh();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _maybeRefresh());
    try {
      _lifecycleListener = AppLifecycleListener(
        onResume: () => unawaited(_maybeRefresh()),
      );
    } catch (_) {
      // AppLifecycleListener needs a live Flutter binding — absent in a
      // plain `test()` context (only `testWidgets()` initializes one),
      // and this method is also reachable from initialize(), which has no
      // surrounding try/catch of its own (a throw there would crash
      // main() before runApp). The periodic timer above still covers
      // refresh regardless of whether app-resume detection is available.
    }
  }

  void _stopBackgroundRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  Future<void> _maybeRefresh() async {
    if (!shouldRefresh(_repository.currentSession())) return;
    try {
      await _repository.refresh();
    } catch (_) {
      // Best-effort — see this class's own doc comment for why a failure
      // here isn't surfaced: the next real API call will hit a genuine
      // 401 and route to login via onUnauthorized if refresh truly can't
      // succeed (e.g. the refresh token itself expired).
    }
  }

  @override
  void dispose() {
    _stopBackgroundRefresh();
    super.dispose();
  }
}
