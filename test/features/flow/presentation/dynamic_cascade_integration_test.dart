// Drives the full DYNAMIC-field cascade (region -> district) through the
// real FlowScreen/RenderingEngineStageScreen rendering path, not just the
// controller in isolation — this is what actually proves the wiring
// (buildStageFieldSchemas -> visibleFieldSchemasFor -> the overlay ->
// kifiya_rendering_engine's DropdownButtonFormField) works end to end.
//
// Gotcha check, per NOTES.md: FakeApiClient/FakeFlowRepository resolve
// without any real delay, so ordinary tester.pump() is enough — no
// Future.delayed-vs-fake-clock polling needed here, same finding as
// flow_screen_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/presentation/flow_notifier.dart';
import 'package:sdui_demo/features/flow/presentation/flow_screen.dart';
import 'package:sdui_demo/services/api_dtos.dart';

import '../../../support/fake_api_client.dart';
import '../../../support/fake_flow_repository.dart';

const List<Map<String, dynamic>> _cascadeStage = [
  {
    'stageId': 'location',
    'title': 'Location',
    'screenType': 'GENERIC_FORM',
    'fields': [
      {
        'key': 'region',
        'label': 'Region',
        'type': 'SELECT',
        'inputMode': 'ENUM',
        'property': {
          'order': 1,
          'isRequired': true,
          'isHidden': false,
          'options': [
            {'label': 'Addis Ababa', 'value': 'addis_ababa'},
            {'label': 'Oromia', 'value': 'oromia'},
          ],
        },
      },
      {
        'key': 'district',
        'label': 'District',
        'type': 'SELECT',
        'inputMode': 'DYNAMIC',
        'property': {
          'order': 2,
          'isRequired': true,
          'isHidden': false,
          'dependsOn': ['region'],
          'dynamicConfig': {
            'endpoint': '/options/regions/{region}/districts',
            'method': 'GET',
          },
        },
      },
    ],
  },
];

Widget _app(FakeApiClient apiClient, FakeFlowRepository repository) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      flowRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: FlowScreen(manifest: FlowManifest(workflowId: 'f', clientId: 'c')),
    ),
  );
}

void main() {
  testWidgets(
    'district enables once region is picked, and repopulates (not the old list) when region changes',
    (tester) async {
      // Keyed by the region *label* ("Addis Ababa"), not a machine value —
      // kifiya_rendering_engine's dropdowns only ever store/submit an
      // option's label, so that's what ends up as district's `region`
      // dependency value. See MockApiClient's own _sampleOptions doc
      // comment.
      final apiClient = FakeApiClient(optionsByEndpoint: {
        FakeApiClient.optionsKey('district', {'region': 'Addis Ababa'}): const [
          FieldOptionDto(label: 'Bole', value: 'bole'),
          FieldOptionDto(label: 'Yeka', value: 'yeka'),
        ],
        FakeApiClient.optionsKey('district', {'region': 'Oromia'}): const [
          FieldOptionDto(label: 'Adama', value: 'adama'),
        ],
      });
      final repository = FakeFlowRepository(stagesJson: _cascadeStage);

      await tester.pumpWidget(_app(apiClient, repository));
      await tester.pump(); // loading
      await tester.pump(); // deferred initState load lands

      // District starts disabled/not-yet-available: no options to open,
      // and its label says so (see RenderingEngineStageScreen's overlay —
      // the plugin's dropdown has no native "disabled" look).
      expect(find.text('District (select a dependency first)'), findsOneWidget);

      // Pick a region.
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      await tester.tap(dropdowns.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Addis Ababa').last);
      await tester.pumpAndSettle();

      // District should now be ready with Addis Ababa's districts.
      expect(find.text('District'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Bole'), findsOneWidget);
      expect(find.text('Yeka'), findsOneWidget);
      await tester.tap(find.text('Bole').last);
      await tester.pumpAndSettle();

      // Change region — district's stale selection must clear, and its
      // list must become Oromia's, not still show Addis Ababa's.
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oromia').last);
      await tester.pumpAndSettle();

      expect(find.text('Bole'), findsNothing); // old selection is gone
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Adama'), findsOneWidget); // new region's list
      expect(find.text('Bole'), findsNothing); // not the old region's list
    },
  );
}
