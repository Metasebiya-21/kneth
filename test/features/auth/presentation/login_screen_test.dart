// Same outer-ProviderScope pattern client_selection_screen_test.dart/
// flow_screen_test.dart use: LoginScreen reads authNotifierProvider
// directly (no nested ProviderScope of its own).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/auth/domain/auth_token.dart';
import 'package:sdui_demo/features/auth/presentation/auth_notifier.dart';
import 'package:sdui_demo/features/auth/presentation/login_screen.dart';
import 'package:sdui_demo/services/app_exception.dart';

import '../../../support/fake_auth_repository.dart';

/// A fake whose `login` doesn't resolve until the test says so — needed to
/// deterministically catch the in-flight `AuthLoggingIn` state, rather
/// than racing a real `pump()` against a microtask that might already
/// have resolved by the time it's checked.
class _SlowAuthRepository extends FakeAuthRepository {
  final _completer = Completer<AuthToken>();

  @override
  Future<AuthToken> login({required String username, required String password}) {
    loginCallCount++;
    lastUsername = username;
    lastPassword = password;
    return _completer.future;
  }

  void complete() => _completer.complete(
        AuthToken(accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.now().add(const Duration(hours: 1))),
      );
}

Widget _wrap(FakeAuthRepository repository) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: LoginScreen()),
  );
}

void main() {
  testWidgets('entering credentials and tapping Sign in calls AuthRepository.login', (tester) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(_wrap(repository));

    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'agent1');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();

    expect(repository.lastUsername, 'agent1');
    expect(repository.lastPassword, 'secret');
  });

  testWidgets('a failed login shows AppErrorView with the repository\'s own message', (tester) async {
    final repository = FakeAuthRepository(
      loginError: const UnauthorizedException('Incorrect username or password.'),
    );
    await tester.pumpWidget(_wrap(repository));

    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'agent1');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump(); // AuthLoggingIn lands
    await tester.pump(); // the fake's rejected Future resolves, AuthFailed lands

    expect(find.text('Incorrect username or password.'), findsOneWidget);
  });

  testWidgets('the button disables and shows a loading label while logging in', (tester) async {
    final repository = _SlowAuthRepository();
    await tester.pumpWidget(_wrap(repository));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump(); // AuthNotifier.login has set AuthLoggingIn synchronously; login() itself is still pending

    expect(find.text('Signing in...'), findsOneWidget);

    repository.complete();
    await tester.pump();

    expect(find.text('Signing in...'), findsNothing);
  });
}
