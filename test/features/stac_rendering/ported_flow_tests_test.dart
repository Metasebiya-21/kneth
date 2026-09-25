// Part 3: the existing tests, ported to the Stac path with their steps and
// expectations kept — flow_screen_test's "starts fresh, renders the first
// stage, advances through to completion" and
// dynamic_cascade_integration_test's region -> district cascade. The Stac
// JSON for each fixture is the REAL backend serializer's output
// (tool/gen_ported_stac_fixtures.py -> test/fixtures/stac/ported_fixtures.json).
//
// Only what the migration deliberately changes differs from the originals (and the
// stage titles are the stage keys, as the backend emits them):
//  * labels come from the field key (the backend has no separate label), so
//    "District" reads "district";
//  * the dropdown stores the option VALUE, so the district dependency is
//    'addis_ababa', not the label 'Addis Ababa' — FakeApiClient's keys below
//    show it, and it is the one line that differs from the old test's fixture;
//  * a NATIVE_CAPTURE stage with an unrecognized handler renders the
//    kneth_native_capture notice instead of the old placeholder text.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/data/stac_manifest_mapper.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/presentation/flow_notifier.dart';
import 'package:sdui_demo/features/flow/presentation/flow_screen.dart';
import 'package:sdui_demo/services/api_dtos.dart';

import '../../support/fake_api_client.dart';
import '../../support/fake_flow_repository.dart';

Map<String, Map<String, dynamic>> _ported() {
  final raw = jsonDecode(File('test/fixtures/stac/ported_fixtures.json').readAsStringSync()) as Map<String, dynamic>;
  return {for (final e in raw.entries) if (e.value is Map) e.key: (e.value as Map).cast<String, dynamic>()};
}


Widget _app(FakeApiClient apiClient, FakeFlowRepository repository) => ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        flowRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(home: FlowScreen(manifest: FlowManifest(workflowId: 'f', clientId: 'c'))),
    );

void main() {
  testWidgets('PORT of flow_screen_test: starts fresh, renders the first stage, advances through to completion',
      (tester) async {
    final ported = _ported();
    final apiClient = FakeApiClient()..stacStages = [ported['stage_a']!, ported['stage_b']!];
    final repository = FakeFlowRepository(stagesJson: stacStagesToStageJson([ported['stage_a']!, ported['stage_b']!]));

    await tester.pumpWidget(_app(apiClient, repository));
    await tester.pump(); // let the loading spinner show
    await tester.pumpAndSettle(); // deferred initState load + the Stac manifest fetch

    expect(find.text('stage_a'), findsOneWidget);
    expect(repository.fetchManifestCallCount, 1);

    // GENERIC_FORM stage with no fields — Continue should submit trivially.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    // Now on the NATIVE_CAPTURE stage with an unrecognized handler.
    expect(find.textContaining("'unrecognized_handler'"), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Flow complete'), findsOneWidget);
  });

  testWidgets(
    'PORT of dynamic_cascade_integration_test: district enables once region is picked, and repopulates (not the old list) '
    'when region changes',
    (tester) async {
      // Keyed by the region VALUE — the one intended difference from the old
      // test, which keyed by the label because the old engine stored labels.
      final apiClient = FakeApiClient(optionsByEndpoint: {
        FakeApiClient.optionsKey('district', {'region': 'addis_ababa'}): const [
          FieldOptionDto(label: 'Bole', value: 'bole'),
          FieldOptionDto(label: 'Yeka', value: 'yeka'),
        ],
        FakeApiClient.optionsKey('district', {'region': 'oromia'}): const [
          FieldOptionDto(label: 'Adama', value: 'adama'),
        ],
      })
        ..stacStages = [_ported()['location']!];
      final repository = FakeFlowRepository(stagesJson: stacStagesToStageJson([_ported()['location']!]));

      await tester.pumpWidget(_app(apiClient, repository));
      await tester.pump(); // loading
      await tester.pumpAndSettle(); // deferred initState load + the Stac manifest fetch

      // District starts not-yet-available: no options, and its label says so.
      expect(find.text('district (select a dependency first)'), findsWidgets);

      // Pick a region.
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      await tester.tap(dropdowns.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Addis Ababa').last);
      await tester.pumpAndSettle();
      expect(apiClient.fetchOptionsDependencyValues.single, {'region': 'addis_ababa'});

      // District should now be ready with Addis Ababa's districts.
      expect(find.text('district (select a dependency first)'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Bole'), findsOneWidget);
      expect(find.text('Yeka'), findsOneWidget);
      await tester.tap(find.text('Bole').last);
      await tester.pumpAndSettle();

      // Change region — district's stale selection must clear, and its list
      // must become Oromia's, not still show Addis Ababa's.
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
