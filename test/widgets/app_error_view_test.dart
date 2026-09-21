import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/services/app_exception.dart';
import 'package:sdui_demo/widgets/app_error_view.dart';

Future<void> _pump(WidgetTester tester, AppException error, {VoidCallback? onRetry}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AppErrorView(error: error, onRetry: onRetry)),
    ),
  );
}

void main() {
  testWidgets('NetworkException gets offline-appropriate messaging, never a raw toString', (tester) async {
    await _pump(tester, const NetworkException(), onRetry: () {});

    expect(find.textContaining('offline'), findsOneWidget);
    expect(find.text(const NetworkException().toString()), findsNothing);
    expect(find.byType(ElevatedButton), findsOneWidget); // retryable
  });

  testWidgets('AppTimeoutException shows a retry button and a plain-language message', (tester) async {
    await _pump(tester, const AppTimeoutException(), onRetry: () {});

    expect(find.textContaining('too long'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });

  testWidgets('ServerException shows a retry button', (tester) async {
    await _pump(tester, const ServerException(500), onRetry: () {});

    expect(find.textContaining('our end'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });

  testWidgets('UnauthorizedException has no retry button, even when onRetry is provided', (tester) async {
    await _pump(tester, const UnauthorizedException(), onRetry: () {});

    expect(find.textContaining('sign in'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing); // not retryable
  });

  testWidgets('UnauthorizedException shows its own custom message, not a hardcoded one', (tester) async {
    await _pump(tester, const UnauthorizedException('Incorrect username or password.'));

    expect(find.text('Incorrect username or password.'), findsOneWidget);
  });

  testWidgets('ForbiddenException has no retry button and shows its own message', (tester) async {
    await _pump(tester, const ForbiddenException(), onRetry: () {});

    expect(find.text(const ForbiddenException().message), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('ClientException has no retry button and shows its own message', (tester) async {
    await _pump(tester, const ClientException(422, 'That field is invalid.'), onRetry: () {});

    expect(find.text('That field is invalid.'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('ParseException has no retry button', (tester) async {
    await _pump(tester, const ParseException(), onRetry: () {});

    expect(find.textContaining('unexpected response'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('UnknownException has no retry button', (tester) async {
    await _pump(tester, const UnknownException(), onRetry: () {});

    expect(find.textContaining('unexpected'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('a retryable exception with no onRetry callback still shows no button', (tester) async {
    await _pump(tester, const NetworkException());

    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('tapping Retry calls onRetry', (tester) async {
    var retried = false;
    await _pump(tester, const ServerException(500), onRetry: () => retried = true);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(retried, isTrue);
  });
}
