// The forgot-password flow, entered the real way — from LoginScreen's
// "Forgot password?" — with a scripted FakeAuthRepository.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/auth/presentation/auth_notifier.dart';
import 'package:sdui_demo/features/auth/presentation/forgot_password_screen.dart';
import 'package:sdui_demo/features/auth/presentation/login_screen.dart';
import 'package:sdui_demo/services/app_exception.dart';
import 'package:sdui_demo/widgets/password_field.dart';

import '../../../support/fake_auth_repository.dart';

Future<FakeAuthRepository> _openFromLogin(WidgetTester tester, {String typedUsername = ''}) async {
  final repository = FakeAuthRepository();
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: LoginScreen()),
  ));
  if (typedUsername.isNotEmpty) {
    await tester.enterText(find.widgetWithText(TextField, 'Username'), typedUsername);
  }
  await tester.tap(find.widgetWithText(TextButton, 'Forgot password?'));
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _requestCode(WidgetTester tester, String username) async {
  await tester.enterText(find.widgetWithText(TextField, 'Username'), username);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Send code'));
  await tester.pump();
}

Future<void> _submitReset(WidgetTester tester, {String code = '123456', String password = 'New-pass-99', String? confirm}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Code'), code);
  await tester.enterText(find.widgetWithText(TextField, 'New password'), password);
  await tester.enterText(find.widgetWithText(TextField, 'Confirm new password'), confirm ?? password);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Reset password'));
  await tester.pump();
}

TextButton _resendButton(WidgetTester tester) => tester.widget<TextButton>(
      find.ancestor(of: find.textContaining('Resend code'), matching: find.byType(TextButton)),
    );

void main() {
  testWidgets('the username typed on the login screen is carried over', (tester) async {
    await _openFromLogin(tester, typedUsername: 'agent-7');
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'agent-7'), findsOneWidget);
  });

  testWidgets('no enumeration: any username gets the same fixed message and the same next step', (tester) async {
    for (final username in ['agent-7', 'no-such-user']) {
      final repository = await _openFromLogin(tester);
      await _requestCode(tester, username);
      expect(repository.calls, ['sendCode:$username']);
      expect(find.text(resetCodeSentMessage), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Code'), findsOneWidget);
      // New tree per iteration.
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('an empty username is caught locally, with no request', (tester) async {
    final repository = await _openFromLogin(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send code'));
    await tester.pump();
    expect(find.text('Enter your username.'), findsOneWidget);
    expect(repository.calls, isEmpty);
  });

  testWidgets('the per-IP 429 on send is shown as "Too many attempts", and the step does not advance', (tester) async {
    final repository = await _openFromLogin(tester);
    repository.sendCodeError = const ClientException(429, 'Too many OTP requests. Please try again later.');
    await _requestCode(tester, 'agent-7');
    expect(find.text('Too many attempts'), findsOneWidget);
    expect(find.text('Too many OTP requests. Please try again later.'), findsOneWidget);
    expect(find.text(resetCodeSentMessage), findsNothing);
  });

  testWidgets('resend is disabled for the cooldown, counts down, then calls /otp/resend and restarts it',
      (tester) async {
    final repository = await _openFromLogin(tester);
    await _requestCode(tester, 'agent-7');

    expect(find.text('Resend code in 60s'), findsOneWidget);
    expect(_resendButton(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resend code in 30s'), findsOneWidget);
    expect(_resendButton(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Resend code'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Resend code'));
    await tester.pump();
    expect(repository.calls, ['sendCode:agent-7', 'resendCode:agent-7']);
    expect(find.text('Resend code in 60s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 61)); // let the ticker finish
  });

  testWidgets('both new-password inputs are the shared PasswordField', (tester) async {
    await _openFromLogin(tester);
    await _requestCode(tester, 'agent-7');
    expect(find.byType(PasswordField), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('success returns to sign-in with the username filled in and a confirmation', (tester) async {
    final repository = await _openFromLogin(tester);
    await _requestCode(tester, 'agent-7');
    await _submitReset(tester);
    await tester.pumpAndSettle();

    expect(repository.resetPasswordCalls.single, {'username': 'agent-7', 'code': '123456', 'new': 'New-pass-99'});
    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.widgetWithText(TextField, 'agent-7'), findsOneWidget);
    expect(find.text('Password reset. Sign in with your new password.'), findsOneWidget);
  });

  testWidgets('local checks: missing code, short password, mismatch — no request', (tester) async {
    final repository = await _openFromLogin(tester);
    await _requestCode(tester, 'agent-7');
    await _submitReset(tester, code: '');
    expect(find.text('Enter the code from the SMS.'), findsOneWidget);
    await _submitReset(tester, password: 'short');
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    await _submitReset(tester, confirm: 'Other-pass-99');
    expect(find.text('The passwords don’t match.'), findsOneWidget);
    expect(repository.resetPasswordCalls, isEmpty);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('a wrong/expired code (422) is shown as a correctable input problem', (tester) async {
    final repository = await _openFromLogin(tester);
    repository.resetPasswordError = const ClientException(422, 'Invalid or expired OTP.');
    await _requestCode(tester, 'agent-7');
    await _submitReset(tester);
    await tester.pump();
    expect(find.text('Check what you entered'), findsOneWidget);
    expect(find.text('Invalid or expired OTP.'), findsOneWidget);
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('a 429 on reset (code thrown away) is shown distinctly AND unlocks resend immediately', (tester) async {
    final repository = await _openFromLogin(tester);
    repository.resetPasswordError = const ClientException(429, 'Too many attempts. Request a new OTP.');
    await _requestCode(tester, 'agent-7');
    expect(_resendButton(tester).onPressed, isNull);

    await _submitReset(tester);
    await tester.pump();
    expect(find.text('Too many attempts'), findsOneWidget);
    expect(find.text('Too many attempts. Request a new OTP.'), findsOneWidget);
    expect(find.text('Resend code'), findsOneWidget);
    expect(_resendButton(tester).onPressed, isNotNull);
  });
}
