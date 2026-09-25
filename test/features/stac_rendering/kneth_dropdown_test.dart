import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/services/app_exception.dart';

import '../../support/fake_api_client.dart';
import '../../support/stac_fixtures.dart';
import 'stac_test_actions.dart';
import 'stac_test_harness.dart';

FakeApiClient _apiWithRealDistricts() {
  final byRegion = recordedDistrictOptionsByRegionValue();
  return FakeApiClient(optionsByEndpoint: {
    for (final e in byRegion.entries) FakeApiClient.optionsKey('district', {'region': e.key}): e.value,
  });
}

void main() {
  group('static / eager options', () {
    testWidgets('stores the option VALUE, not its label, while showing the label', (tester) async {
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(
        widgetJson: {
          'type': 'column',
          'children': [
            {
              'type': 'kneth_dropdown',
              'id': 'region',
              'label': 'region',
              'required': false,
              'options': [
                {'label': 'Addis Ababa', 'value': 'addis_ababa'},
                {'label': 'Oromia', 'value': 'oromia'},
              ],
            },
          ],
        },
        submitted: submitted,
      ));
      await tester.pumpAndSettle();

      await pickOption(tester, 'Addis Ababa');
      expect(find.text('Addis Ababa'), findsWidgets, reason: 'the label is what the agent sees');
      await tapContinue(tester);

      expect(submitted.single, {'region': 'addis_ababa'});
    });

    testWidgets('required: blocked with "<label> is required" until a value is chosen', (tester) async {
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(
        widgetJson: {
          'type': 'kneth_dropdown',
          'id': 'kind',
          'label': 'kind',
          'required': true,
          'options': [
            {'label': 'A', 'value': 'a'},
          ],
        },
        submitted: submitted,
      ));
      await tester.pumpAndSettle();
      await tapContinue(tester);
      expect(find.text('kind is required'), findsOneWidget);

      await pickOption(tester, 'A');
      await tapContinue(tester);
      expect(submitted.single, {'kind': 'a'});
    });

    testWidgets('a seeded value that matches an option is shown as the label of that option', (tester) async {
      await tester.pumpWidget(stacStageApp(
        widgetJson: {
          'type': 'kneth_dropdown',
          'id': 'k',
          'label': 'k',
          'required': false,
          'options': [
            {'label': 'A', 'value': 'a'},
          ],
        },
        submitted: [],
        initialValues: {'k': 'a'},
      ));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsWidgets);
    });
  });

  group('live DYNAMIC options (the real recorded region -> district stage)', () {
    testWidgets('district is not ready until region has a value, then fetches with the region VALUE (a UUID)',
        (tester) async {
      final api = _apiWithRealDistricts();
      await tester.pumpWidget(stacStageApp(widgetJson: recordedStacWidget('location'), submitted: [], apiClient: api));
      await tester.pumpAndSettle();

      expect(find.text('district (select a dependency first)'), findsWidgets);
      expect(api.fetchOptionsCallCount, 0);

      await pickOption(tester, 'Addis Ababa', index: 0);

      expect(api.fetchOptionsCallCount, 1);
      expect(api.fetchOptionsFieldKeys.single, 'district');
      final sent = api.fetchOptionsDependencyValues.single['region']!;
      expect(sent, recordedRegionValue('Addis Ababa'));
      expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(sent), isTrue, reason: 'the backend requires a UUID here');
      expect(find.text('district'), findsWidgets);
      expect(find.text('district (select a dependency first)'), findsNothing);
    });

    testWidgets('changing region clears the stale district, refetches, and shows only the new region\'s districts',
        (tester) async {
      final api = _apiWithRealDistricts();
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(
        widgetJson: recordedStacWidget('location'),
        submitted: submitted,
        apiClient: api,
      ));
      await tester.pumpAndSettle();

      await pickOption(tester, 'Addis Ababa', index: 0);
      await pickOption(tester, 'Bole', index: 1);

      await pickOption(tester, 'Oromia', index: 0);

      expect(api.fetchOptionsCallCount, 2);
      expect(api.fetchOptionsDependencyValues.last['region'], recordedRegionValue('Oromia'));

      // Stale selection gone: Continue reports district missing rather than
      // submitting Bole under Oromia.
      await tester.enterText(textFieldLabelled('postal_code'), '1000');
      await tapContinue(tester);
      expect(find.text('district is required'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Adama'), findsWidgets);
      expect(find.text('Jimma'), findsWidgets);
      expect(find.text('Bole'), findsNothing);
    });

    testWidgets('the picked district is stored as its real value',
        (tester) async {
      final api = _apiWithRealDistricts();
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(widgetJson: recordedStacWidget('location'), submitted: submitted, apiClient: api));
      await tester.pumpAndSettle();

      await pickOption(tester, 'Addis Ababa', index: 0);
      await pickOption(tester, 'Kirkos', index: 1);
      await tester.enterText(textFieldLabelled('postal_code'), '1000');
      await tapContinue(tester);

      final kirkos = recordedDistrictOptionsByRegionValue()[recordedRegionValue('Addis Ababa')]!
          .firstWhere((o) => o.label == 'Kirkos')
          .value;
      expect(submitted.single, {
        'region': recordedRegionValue('Addis Ababa'),
        'district': kirkos,
        'postal_code': '1000',
      });
    });

    testWidgets('a cleared dependent keeps an explicit null in the values map (same as the old engine\'s updateField)',
        (tester) async {
      final api = _apiWithRealDistricts();
      final submitted = <Map<String, dynamic>>[];
      final json = {
        'type': 'column',
        'children': [
          ...(recordedStacWidget('location')['children'] as List).cast<Map<String, dynamic>>().map((c) =>
              {...c, 'required': false}),
        ],
      };
      await tester.pumpWidget(stacStageApp(widgetJson: json, submitted: submitted, apiClient: api));
      await tester.pumpAndSettle();

      await pickOption(tester, 'Addis Ababa', index: 0);
      await pickOption(tester, 'Bole', index: 1);
      await pickOption(tester, 'Oromia', index: 0);
      await tapContinue(tester);

      expect(submitted.single, {'region': recordedRegionValue('Oromia'), 'district': null});
    });

    testWidgets('shows "(loading...)" while the fetch is in flight', (tester) async {
      final api = _apiWithRealDistricts()..fetchOptionsGate = Completer<void>();
      await tester.pumpWidget(stacStageApp(widgetJson: recordedStacWidget('location'), submitted: [], apiClient: api));
      await tester.pumpAndSettle();

      await pickOption(tester, 'Addis Ababa', index: 0);
      expect(find.text('district (loading...)'), findsWidgets);

      api.fetchOptionsGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('district (loading...)'), findsNothing);
    });

    testWidgets('a failed fetch renders the shared AppErrorView, and Retry re-fetches through the real controller',
        (tester) async {
      final api = _apiWithRealDistricts()..fetchOptionsError = const NetworkException();
      await tester.pumpWidget(stacStageApp(widgetJson: recordedStacWidget('location'), submitted: [], apiClient: api));
      await tester.pumpAndSettle();

      await pickOption(tester, 'Addis Ababa', index: 0);

      expect(find.textContaining("You appear to be offline"), findsOneWidget);
      expect(find.text('district (failed to load)'), findsWidgets);
      expect(api.fetchOptionsCallCount, 1);

      api.fetchOptionsError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.fetchOptionsCallCount, 2);
      expect(find.textContaining('You appear to be offline'), findsNothing);
      expect(find.text('district'), findsWidgets);
    });
  });
}
