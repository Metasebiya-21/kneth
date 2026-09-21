// Exercises AuthNotifier directly — a plain StateNotifier, no Riverpod
// container needed, same reasoning DynamicOptionsController/FlowCaseState
// tests already use. Background refresh's *timer* itself isn't asserted
// on here (that would mean real or fake-clock waits); token_refresh_
// policy_test.dart already covers the pure "when should this refresh"
// decision in isolation. Every notifier created here is disposed at the
// end of its test so no Timer/AppLifecycleListener leaks between tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/auth/presentation/auth_notifier.dart';
import 'package:sdui_demo/services/app_exception.dart';

import '../../../support/fake_auth_repository.dart';

void main() {
  test('starts logged out when the repository has no session after initialize()', () async {
    final repository = FakeAuthRepository();
    final notifier = AuthNotifier(repository);
    addTearDown(notifier.dispose);

    expect(notifier.state, isA<AuthCheckingStorage>());
    await notifier.initialize();

    expect(notifier.state, isA<AuthLoggedOut>());
    expect(repository.initializeCallCount, 1);
  });

  test('login success moves to AuthLoggedIn and forwards username/password', () async {
    final repository = FakeAuthRepository();
    final notifier = AuthNotifier(repository);
    addTearDown(notifier.dispose);

    await notifier.login(username: 'agent1', password: 'secret');

    expect(notifier.state, isA<AuthLoggedIn>());
    expect(repository.lastUsername, 'agent1');
    expect(repository.lastPassword, 'secret');
  });

  test('a login failure surfaces the exact AppException, unchanged, as AuthFailed', () async {
    const failure = UnauthorizedException('Incorrect username or password.');
    final repository = FakeAuthRepository(loginError: failure);
    final notifier = AuthNotifier(repository);
    addTearDown(notifier.dispose);

    await notifier.login(username: 'agent1', password: 'wrong');

    expect(notifier.state, isA<AuthFailed>());
    expect((notifier.state as AuthFailed).error, same(failure));
  });

  test('a non-AppException login failure is wrapped, not left as a raw exception type', () async {
    final repository = FakeAuthRepository(loginError: Exception('boom'));
    final notifier = AuthNotifier(repository);
    addTearDown(notifier.dispose);

    await notifier.login(username: 'agent1', password: 'wrong');

    expect(notifier.state, isA<AuthFailed>());
    expect((notifier.state as AuthFailed).error, isA<UnknownException>());
  });

  test('logout clears the repository and moves to AuthLoggedOut', () async {
    final repository = FakeAuthRepository();
    final notifier = AuthNotifier(repository);
    addTearDown(notifier.dispose);
    await notifier.login(username: 'agent1', password: 'secret');

    await notifier.logout();

    expect(notifier.state, isA<AuthLoggedOut>());
    expect(repository.logoutCallCount, 1);
  });

  test('forceLogout moves to AuthLoggedOut immediately, same as what ApiClientImpl.onUnauthorized triggers',
      () async {
    final repository = FakeAuthRepository();
    final notifier = AuthNotifier(repository);
    addTearDown(notifier.dispose);
    await notifier.login(username: 'agent1', password: 'secret');
    expect(notifier.state, isA<AuthLoggedIn>());

    notifier.forceLogout();

    expect(notifier.state, isA<AuthLoggedOut>());
  });
}
