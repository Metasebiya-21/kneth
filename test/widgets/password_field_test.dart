import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/widgets/password_field.dart';

bool _obscured(WidgetTester tester, String label) =>
    tester.widget<TextField>(find.widgetWithText(TextField, label)).obscureText;

void main() {
  testWidgets('starts obscured; the eye toggles show/hide; each field has its own state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          PasswordField(controller: TextEditingController(), labelText: 'One'),
          PasswordField(controller: TextEditingController(), labelText: 'Two'),
        ]),
      ),
    ));

    expect(_obscured(tester, 'One'), isTrue);
    expect(_obscured(tester, 'Two'), isTrue);

    await tester.tap(find.descendant(of: find.widgetWithText(TextField, 'One'), matching: find.byTooltip('Show password')));
    await tester.pump();
    expect(_obscured(tester, 'One'), isFalse);
    expect(_obscured(tester, 'Two'), isTrue, reason: 'toggling one field must not reveal another');
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(_obscured(tester, 'One'), isTrue);
  });

  testWidgets('revealing never turns on autocorrect/suggestions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PasswordField(controller: TextEditingController(), labelText: 'P')),
    ));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets('keeps the typed text when toggled', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PasswordField(controller: controller, labelText: 'P'))));
    await tester.enterText(find.byType(TextField), 's3cret-pass');
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(controller.text, 's3cret-pass');
    expect(find.text('s3cret-pass'), findsOneWidget);
  });
}
