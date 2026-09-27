// ChangePasswordScreen driven through a real AuthNotifier (fake repository),
// reached the real way: a login answered with "temporary password must be
// changed".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/auth/domain/auth_token.dart';
import 'package:sdui_demo/features/auth/domain/password_change_required.dart';
import 'package:sdui_demo/features/auth/presentation/auth_notifier.dart';
import 'package:sdui_demo/features/auth/presentation/change_password_screen.dart';
import 'package:sdui_demo/services/app_exception.dart';
import 'package:sdui_demo/widgets/password_field.dart';

import '../../../support/fake_auth_repository.dart';

class _FirstLoginRepository extends FakeAuthRepository {
  @override
  Future<AuthToken> login({required String username, required String password}) {
    if (changePasswordCalls.isEmpty || changePasswordError != null) {
      throw PasswordChangeRequiredException(username: username, message: 'must change');
    }
    return super.login(username: username, password: password);
  }
}

Future<(_FirstLoginRepository, AuthNotifier)> _pump(WidgetTester tester) async {
  final repository = _FirstLoginRepository();
  final notifier = AuthNotifier(repository);
  await notifier.login(username: 'agent-7', password: 'Temp-123');
  await tester.pumpWidget(ProviderScope(
    overrides: [authNotifierProvider.overrideWith((ref) => notifier)],
    child: const MaterialApp(home: ChangePasswordScreen()),
  ));
  return (repository, notifier);
}

Future<void> _fill(WidgetTester tester, {String current = 'Temp-123', String next = 'New-pass-99', String? confirm}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Temporary password'), current);
  await tester.enterText(find.widgetWithText(TextField, 'New password'), next);
  await tester.enterText(find.widgetWithText(TextField, 'Confirm new password'), confirm ?? next);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Save and sign in'));
  await tester.pump();
}

void main() {
  testWidgets('all three password inputs are the shared PasswordField (with the visibility toggle)', (tester) async {
    await _pump(tester);
    expect(find.byType(PasswordField), findsNWidgets(3));
    expect(find.byTooltip('Show password'), findsNWidgets(3));
  });

  testWidgets('success: calls change with the typed passwords and ends signed in', (tester) async {
    final (repository, notifier) = await _pump(tester);
    await _fill(tester);
    await tester.pumpAndSettle();
    expect(repository.changePasswordCalls.single, {'username': 'agent-7', 'current': 'Temp-123', 'new': 'New-pass-99'});
    expect(repository.lastPassword, 'New-pass-99');
    expect(notifier.state, isA<AuthLoggedIn>());
  });

  testWidgets('local checks stop obvious mistakes before any request: short, unchanged, mismatched, empty',
      (tester) async {
    final (repository, _) = await _pump(tester);

    await _fill(tester, next: 'short');
    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    await _fill(tester, next: 'Temp-123');
    expect(find.text('Choose a password different from your current one.'), findsOneWidget);

    await _fill(tester, confirm: 'Something-else');
    expect(find.text('The passwords don’t match.'), findsOneWidget);

    await _fill(tester, current: '');
    expect(find.text('Enter your temporary password.'), findsOneWidget);

    expect(repository.changePasswordCalls, isEmpty);
  });

  for (final (label, error, title) in [
    ('401', const UnauthorizedException('Invalid username or password'), 'Current password is incorrect'),
    ('422', const ClientException(422, 'New password does not meet the password policy.'), 'Check what you entered'),
    ('429', const ClientException(429, 'Too many attempts. Please try again later.'), 'Too many attempts'),
  ]) {
    testWidgets('a $label is shown distinctly, with the backend\'s own message, and the form stays usable',
        (tester) async {
      final (repository, notifier) = await _pump(tester);
      repository.changePasswordError = error;
      await _fill(tester);
      await tester.pump();

      expect(find.text(title), findsOneWidget);
      expect(find.text(error.message), findsOneWidget);
      expect(notifier.state, isA<AuthPasswordChangeRequired>());
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
    });
  }

  testWidgets('offline is rendered by the shared AppErrorView, not the auth banner', (tester) async {
    final (repository, _) = await _pump(tester);
    repository.changePasswordError = const NetworkException();
    await _fill(tester);
    await tester.pump();
    expect(find.textContaining('offline'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-error-banner')), findsNothing);
  });

  testWidgets('the close button returns to sign-in (AuthLoggedOut)', (tester) async {
    final (_, notifier) = await _pump(tester);
    await tester.tap(find.byTooltip('Back to sign in'));
    await tester.pump();
    expect(notifier.state, isA<AuthLoggedOut>());
  });
}
