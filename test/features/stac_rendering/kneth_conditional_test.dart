// kneth_conditional against the REAL recorded association_details stage
// (association_type / company_name — the same fixture the scoping spike
// used, now produced by the real backend's serializer). The visibility and
// required-ness under test come from the app's existing
// FieldConfig.effectiveState, not from the parser.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/stac_fixtures.dart';
import 'stac_test_actions.dart';
import 'stac_test_harness.dart';

Widget _app(List<Map<String, dynamic>> submitted, {Map<String, dynamic>? widgetJson, Map<String, dynamic> initial = const {}}) =>
    stacStageApp(
      widgetJson: widgetJson ?? recordedStacWidget('association_details'),
      submitted: submitted,
      initialValues: initial,
    );

void main() {
  testWidgets('company_name is hidden until Group is picked, then shown', (tester) async {
    await tester.pumpWidget(_app([]));
    await tester.pumpAndSettle();

    expect(textFieldLabelled('company_name'), findsNothing);
    await pickOption(tester, 'Group');
    expect(textFieldLabelled('company_name'), findsOneWidget);
  });

  testWidgets('then.isRequired makes it required: Continue is blocked with "company_name is required"', (tester) async {
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(_app(submitted));
    await tester.pumpAndSettle();
    await pickOption(tester, 'Group');

    await tapContinue(tester);

    expect(find.text('company_name is required'), findsOneWidget);
    expect(submitted, isEmpty);

    await tester.enterText(textFieldLabelled('company_name'), 'Acme');
    await tapContinue(tester);
    expect(submitted.single, {'association_type': 'Group', 'company_name': 'Acme'});
  });

  testWidgets('switching back to Individual hides it again, and a hidden field is not validated', (tester) async {
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(_app(submitted));
    await tester.pumpAndSettle();
    await pickOption(tester, 'Group');
    expect(textFieldLabelled('company_name'), findsOneWidget);

    await pickOption(tester, 'Individual');
    expect(textFieldLabelled('company_name'), findsNothing);

    await tapContinue(tester);
    expect(submitted.single, {'association_type': 'Individual'});
  });

  testWidgets('a sibling text field keeps its text through the toggles (subtree is not re-parsed)', (tester) async {
    final widgetJson = {
      'type': 'column',
      'children': [
        {'type': 'kneth_text', 'id': 'full_name', 'label': 'full_name', 'required': false},
        ...((recordedStacWidget('association_details')['children']) as List).cast<Map<String, dynamic>>(),
      ],
    };
    await tester.pumpWidget(_app([], widgetJson: widgetJson));
    await tester.pumpAndSettle();
    await tester.enterText(textFieldLabelled('full_name'), 'Ada');

    await pickOption(tester, 'Group');
    await pickOption(tester, 'Individual');

    expect(find.widgetWithText(TextField, 'Ada'), findsOneWidget);
  });

  testWidgets('multi-clause "if" is an AND, evaluated by the existing ConditionalDependency', (tester) async {
    Map<String, dynamic> select(String id, List<String> values) => {
          'type': 'kneth_dropdown',
          'id': id,
          'label': id,
          'required': false,
          'options': [for (final v in values) {'label': v, 'value': v}],
        };
    final widgetJson = {
      'type': 'column',
      'children': [
        select('a', ['x', 'other']),
        select('b', ['y', 'other']),
        {
          'type': 'kneth_conditional',
          'property': {
            'isRequired': false,
            'isHidden': true,
            'dependsOn': ['a', 'b'],
            'conditionalDependency': {
              'if': [
                {'field': 'a', 'op': 'eq', 'value': 'x'},
                {'field': 'b', 'op': 'eq', 'value': 'y'},
              ],
              'then': {'isHidden': false},
              'else': {'isHidden': true},
            },
          },
          'child': {'type': 'kneth_text', 'id': 'both', 'label': 'both', 'required': false},
        },
      ],
    };
    await tester.pumpWidget(_app([], widgetJson: widgetJson));
    await tester.pumpAndSettle();

    await pickOption(tester, 'x', index: 0);
    expect(textFieldLabelled('both'), findsNothing, reason: 'only one of the two clauses holds');
    await pickOption(tester, 'y', index: 1);
    expect(textFieldLabelled('both'), findsOneWidget);

    // ...and it flips back when EITHER clause stops holding (port of
    // the removed adapter's AND-visibility test).
    await pickOption(tester, 'other', index: 0);
    expect(textFieldLabelled('both'), findsNothing);
    await pickOption(tester, 'x', index: 0);
    expect(textFieldLabelled('both'), findsOneWidget);
    await pickOption(tester, 'other', index: 1);
    expect(textFieldLabelled('both'), findsNothing);
  });

  testWidgets('item 1: a value typed while visible is DROPPED (key absent) once the field is hidden again', (tester) async {
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(_app(submitted));
    await tester.pumpAndSettle();
    await pickOption(tester, 'Group');
    await tester.enterText(textFieldLabelled('company_name'), 'Acme');
    await pickOption(tester, 'Individual');

    await tapContinue(tester);

    expect(submitted.single, {'association_type': 'Individual'});
    expect(submitted.single.containsKey('company_name'), isFalse);
  });

  testWidgets('item 1 regression: hidden, shown again and filled: the current value IS submitted', (tester) async {
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(_app(submitted));
    await tester.pumpAndSettle();
    await pickOption(tester, 'Group');
    await tester.enterText(textFieldLabelled('company_name'), 'Acme');
    await pickOption(tester, 'Individual');
    await pickOption(tester, 'Group');
    expect(find.widgetWithText(TextField, 'Acme'), findsOneWidget, reason: 'restored on re-show');

    await tapContinue(tester);
    expect(submitted.single, {'association_type': 'Group', 'company_name': 'Acme'});
  });

  testWidgets('item 1: a seeded value for a statically hidden field (visibility:false) is not submitted', (tester) async {
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(stacStageApp(
      widgetJson: {
        'type': 'column',
        'children': [
          {'type': 'kneth_text', 'id': 'shown', 'label': 'shown', 'required': false},
          {
            'type': 'visibility',
            'visible': false,
            'child': {'type': 'kneth_text', 'id': 'secret', 'label': 'secret', 'required': false},
          },
        ],
      },
      submitted: submitted,
      initialValues: {'secret': 'prefilled', 'shown': 'x'},
    ));
    await tester.pumpAndSettle();
    await tapContinue(tester);
    expect(submitted.single, {'shown': 'x'});
  });
}
