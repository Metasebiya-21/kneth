import 'package:flutter_test/flutter_test.dart';

import 'stac_test_actions.dart';
import 'stac_test_harness.dart';

void main() {
  testWidgets('kneth_unsupported_field renders a notice in place, without taking the rest of the stage down',
      (tester) async {
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(stacStageApp(
      widgetJson: {
        'type': 'column',
        'children': [
          {'type': 'kneth_text', 'id': 'name', 'label': 'name', 'required': false},
          {'type': 'kneth_unsupported_field', 'id': 'odd', 'fieldType': 'SELECT', 'inputMode': 'FREE'},
        ],
      },
      submitted: submitted,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining("'odd' can't be shown in this version of the app"), findsOneWidget);
    expect(find.textContaining('SELECT/FREE'), findsOneWidget);

    await tester.enterText(textFieldLabelled('name'), 'Ada');
    await tapContinue(tester);
    expect(submitted.single, {'name': 'Ada'}, reason: 'the marker is non-blocking and contributes no value');
  });

  testWidgets('kneth_native_capture names the unsupported handler, and Continue still works (old placeholder submitted {})',
      (tester) async {
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(stacStageApp(
      widgetJson: {'type': 'kneth_native_capture', 'id': 'liveness', 'label': 'liveness', 'handler': 'face_liveness'},
      submitted: submitted,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining("'face_liveness'"), findsOneWidget);
    await tapContinue(tester);
    expect(submitted.single, isEmpty);
  });

  testWidgets('kneth_native_capture without a handler still renders', (tester) async {
    await tester.pumpWidget(stacStageApp(
      widgetJson: {'type': 'kneth_native_capture', 'id': 'x', 'label': 'x'},
      submitted: [],
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining("'x' needs a capture type"), findsOneWidget);
  });

  testWidgets('an unconditionally hidden field (built-in visibility, visible:false) is not shown, not validated, not submitted',
      (tester) async {
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(stacStageApp(
      widgetJson: {
        'type': 'column',
        'children': [
          {'type': 'kneth_text', 'id': 'shown', 'label': 'shown', 'required': false},
          {
            'type': 'visibility',
            'visible': false,
            'child': {'type': 'kneth_text', 'id': 'secret', 'label': 'secret', 'required': true},
          },
        ],
      },
      submitted: submitted,
    ));
    await tester.pumpAndSettle();

    expect(textFieldLabelled('secret'), findsNothing);
    await tester.enterText(textFieldLabelled('shown'), 'x');
    await tapContinue(tester);
    expect(submitted.single, {'shown': 'x'}, reason: 'the hidden field is required but never mounted, so never validated');
  });

  testWidgets('a widget type this app version has no parser for does not take the stage down (debug build behaviour)',
      (tester) async {
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(stacStageApp(
      widgetJson: {
        'type': 'column',
        'children': [
          {'type': 'kneth_text', 'id': 'name', 'label': 'name', 'required': false},
          {'type': 'kneth_from_the_future', 'id': 'x'},
        ],
      },
      submitted: submitted,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.enterText(textFieldLabelled('name'), 'Ada');
    await tapContinue(tester);
    expect(submitted.single, {'name': 'Ada'});
  });
}
