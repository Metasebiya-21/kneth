// AuthNotifier's first-login branch: /auth/login's 403 "temporary password
// must be changed" -> AuthPasswordChangeRequired -> completePasswordChange
// (change, then sign in with the new password). Same plain-StateNotifier
// style as auth_notifier_test.dart; notifiers are disposed per test.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/auth/domain/auth_token.dart';
import 'package:sdui_demo/features/auth/domain/password_change_required.dart';
import 'package:sdui_demo/features/auth/presentation/auth_notifier.dart';
import 'package:sdui_demo/services/app_exception.dart';

import '../../../support/fake_auth_repository.dart';

const _required = PasswordChangeRequiredException(
  username: 'agent-7',
  message: 'your temporary password must be changed before you can sign in',
);

/// First login throws [_required]; after a change, login succeeds (or
/// throws [loginAfterChangeError]).
class _FirstLoginRepository extends FakeAuthRepository {
  Object? loginAfterChangeError;
  Completer<void>? changeGate;

  @override
  Future<AuthToken> login({required String username, required String password}) {
    if (changePasswordCalls.isEmpty) {
      loginCallCount++;
      throw _required;
    }
    loginError = loginAfterChangeError;
    return super.login(username: username, password: password);
  }

  @override
  Future<void> changePassword({
    required String username,
    required String currentPassword,
    required String newPassword,
  }) async {
    await changeGate?.future;
    return super.changePassword(username: username, currentPassword: currentPassword, newPassword: newPassword);
  }
}

Future<(AuthNotifier, _FirstLoginRepository)> _atChangeRequired() async {
  final repository = _FirstLoginRepository();
  final notifier = AuthNotifier(repository);
  addTearDown(notifier.dispose);
  await notifier.login(username: 'agent-7', password: 'Temp-123');
  return (notifier, repository);
}

void main() {
  test('a login answered with PasswordChangeRequiredException moves to AuthPasswordChangeRequired, not AuthFailed',
      () async {
    final (notifier, _) = await _atChangeRequired();
    final state = notifier.state;
    expect(state, isA<AuthPasswordChangeRequired>());
    state as AuthPasswordChangeRequired;
    expect(state.username, 'agent-7');
    expect(state.submitting, isFalse);
    expect(state.error, isNull);
  });

  test('completePasswordChange changes the password, then logs in with the NEW one, ending AuthLoggedIn',
      () async {
    final (notifier, repository) = await _atChangeRequired();
    await notifier.completePasswordChange(currentPassword: 'Temp-123', newPassword: 'New-pass-99');

    expect(repository.changePasswordCalls.single, {'username': 'agent-7', 'current': 'Temp-123', 'new': 'New-pass-99'});
    expect(repository.lastUsername, 'agent-7');
    expect(repository.lastPassword, 'New-pass-99');
    expect(notifier.state, isA<AuthLoggedIn>());
  });

  test('while the change is in flight the state is submitting — and never passes through AuthLoggingIn', () async {
    final (notifier, repository) = await _atChangeRequired();
    repository.changeGate = Completer<void>();
    final seen = <AuthState>[];
    final remove = notifier.addListener(seen.add, fireImmediately: false);
    addTearDown(remove);

    final done = notifier.completePasswordChange(currentPassword: 'Temp-123', newPassword: 'New-pass-99');
    expect((notifier.state as AuthPasswordChangeRequired).submitting, isTrue);
    repository.changeGate!.complete();
    await done;

    expect(seen.whereType<AuthLoggingIn>(), isEmpty, reason: 'AuthLoggingIn would flash the login screen');
    expect(seen.last, isA<AuthLoggedIn>());
  });

  for (final (label, error) in [
    ('401 wrong current password', const UnauthorizedException('Invalid username or password')),
    ('422 weak/unchanged', const ClientException(422, 'The new password must be different from the current one.')),
    ('429 rate-limited', const ClientException(429, 'Too many attempts. Please try again later.')),
  ]) {
    test('a failed change ($label) stays on the change step with that exact error, and does not log in', () async {
      final (notifier, repository) = await _atChangeRequired();
      repository.changePasswordError = error;
      final loginsBefore = repository.loginCallCount;

      await notifier.completePasswordChange(currentPassword: 'Temp-123', newPassword: 'New-pass-99');

      final state = notifier.state as AuthPasswordChangeRequired;
      expect(state.error, same(error));
      expect(state.submitting, isFalse);
      expect(state.username, 'agent-7');
      expect(repository.loginCallCount, loginsBefore);
    });
  }

  test('a failed sign-in AFTER a successful change goes to AuthFailed (the password has changed by then)',
      () async {
    final (notifier, repository) = await _atChangeRequired();
    repository.loginAfterChangeError = const NetworkException();
    await notifier.completePasswordChange(currentPassword: 'Temp-123', newPassword: 'New-pass-99');
    expect(notifier.state, isA<AuthFailed>());
    expect((notifier.state as AuthFailed).error, isA<NetworkException>());
  });

  test('if the backend STILL demands a change after one succeeded, that is AuthFailed with an explanation',
      () async {
    final (notifier, repository) = await _atChangeRequired();
    repository.loginAfterChangeError = _required;
    await notifier.completePasswordChange(currentPassword: 'Temp-123', newPassword: 'New-pass-99');
    final state = notifier.state as AuthFailed;
    expect(state.error, isA<ForbiddenException>());
    expect(state.error.message, contains('still needs setup'));
  });

  test('cancelPasswordChange returns to AuthLoggedOut; completePasswordChange outside that state is a no-op',
      () async {
    final (notifier, repository) = await _atChangeRequired();
    notifier.cancelPasswordChange();
    expect(notifier.state, isA<AuthLoggedOut>());

    await notifier.completePasswordChange(currentPassword: 'x', newPassword: 'y-12345678');
    expect(repository.changePasswordCalls, isEmpty);
    expect(notifier.state, isA<AuthLoggedOut>());
  });
}
