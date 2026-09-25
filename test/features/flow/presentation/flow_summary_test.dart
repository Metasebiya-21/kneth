// Item 4 (decided 2026-09-24): the completion summary shows a select field's
// human-readable label, not the stored value (a UUID for reference-data
// fields). Uses the real recorded region/district fixtures.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/data/stac_manifest_mapper.dart';
import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/presentation/flow_notifier.dart';
import 'package:sdui_demo/features/flow/presentation/flow_screen.dart';
import 'package:sdui_demo/services/app_exception.dart';

import '../../../support/fake_api_client.dart';
import '../../../support/fake_flow_repository.dart';
import '../../../support/stac_flow_harness.dart';
import '../../../support/stac_fixtures.dart';

BackendRulesApiClient _api() {
  final byRegion = recordedDistrictOptionsByRegionValue();
  return BackendRulesApiClient(optionsByEndpoint: {
    for (final e in byRegion.entries) FakeApiClient.optionsKey('district', {'region': e.key}): e.value,
  })
    ..stacStages = (recordedStacManifest()['stages'] as List).cast<Map<String, dynamic>>();
}

final _regionUuid = recordedRegionValue('Addis Ababa');
String get _boleUuid =>
    recordedDistrictOptionsByRegionValue()[_regionUuid]!.firstWhere((o) => o.label == 'Bole').value;

/// A case that is ALREADY complete (as after a restart), resumed at the summary.
Widget _completedCase(FakeApiClient api, Map<String, Map<String, dynamic>> collected) {
  final manifest = ResolvedFlowManifest(
    workflowId: 'w',
    clientId: 'c',
    caseId: 'case-1',
    fetchedAt: DateTime.now(),
    stagesJson: stacStagesToStageJson(recordedStacStages(['location'])),
  );
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      flowRepositoryProvider.overrideWithValue(FakeFlowRepository(
        saved: FlowCaseState(manifest: manifest, stageIndex: 1, isComplete: true, collectedValues: collected),
      )),
    ],
    child: MaterialApp(home: FlowScreen(manifest: FlowManifest(workflowId: 'w', clientId: 'c'), resumeMode: true)),
  );
}

void main() {
  testWidgets('after a live Stac run: labels for BOTH the eager region and the live district, from already-fetched data '
      '(no extra network call)', (tester) async {
    final api = _api();
    await tester.pumpWidget(stacFlowApp(
      apiClient: api,
      stacStages: recordedStacStages(['location']),
      workflowId: 'w',
      clientId: 'c',
      caseId: 'case-1',
    ));
    await tester.pumpAndSettle();
    await choose(tester, 'Addis Ababa', dropdown: 0);
    await choose(tester, 'Bole', dropdown: 1);
    await tester.enterText(textFieldWith('postal_code'), '1000');
    await pressContinue(tester);

    expect(find.text('Flow complete'), findsOneWidget);
    final run = ScenarioRun();
    captureResult(tester, run);
    expect(run.allValues['location.region'], _regionUuid, reason: 'the stored value is still the real value');
    expect(run.allValues['location.district'], _boleUuid);

    expect(find.text('Addis Ababa'), findsOneWidget);
    expect(find.text('Bole'), findsOneWidget);
    expect(find.text(_regionUuid), findsNothing);
    expect(find.text(_boleUuid), findsNothing);
    expect(find.text('1000'), findsOneWidget, reason: 'non-select values render exactly as before');
    expect(api.fetchOptionsCallCount, 1, reason: 'only the stage\'s own fetch; the summary used what it had');
  });

  testWidgets('a resumed, already-complete case (empty cache): region label from the manifest, district re-fetched once',
      (tester) async {
    final api = _api();
    await tester.pumpWidget(_completedCase(api, {
      'location': {'region': _regionUuid, 'district': _boleUuid, 'postal_code': '1000'},
    }));
    await tester.pumpAndSettle();

    expect(find.text('Flow complete'), findsOneWidget);
    expect(find.text('Addis Ababa'), findsOneWidget);
    expect(find.text('Bole'), findsOneWidget);
    expect(find.text(_boleUuid), findsNothing);
    expect(api.fetchOptionsCallCount, 1);
    expect(api.fetchOptionsDependencyValues.single, {'region': _regionUuid});
  });

  testWidgets('FALLBACK: options can\'t be re-fetched -> the raw stored value, no crash, not blank', (tester) async {
    final api = _api()..fetchOptionsError = const NetworkException();
    await tester.pumpWidget(_completedCase(api, {
      'location': {'region': _regionUuid, 'district': _boleUuid},
    }));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_boleUuid), findsOneWidget);
    expect(find.text('Addis Ababa'), findsOneWidget, reason: 'the resolvable field still shows its label');
  });

  testWidgets('FALLBACK: the dependency value is missing -> nothing to fetch with; raw value, no network call',
      (tester) async {
    final api = _api();
    await tester.pumpWidget(_completedCase(api, {
      'location': {'district': _boleUuid},
    }));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_boleUuid), findsOneWidget);
    expect(api.fetchOptionsCallCount, 0);
  });

  testWidgets('FALLBACK: a value that matches no option (e.g. stale) shows as stored', (tester) async {
    await tester.pumpWidget(_completedCase(_api(), {
      'location': {'region': 'not-a-real-id'},
    }));
    await tester.pumpAndSettle();
    expect(find.text('not-a-real-id'), findsOneWidget);
  });

  testWidgets('a label stored by an older build still shows correctly (no option has that value)', (tester) async {
    await tester.pumpWidget(_completedCase(_api(), {
      'location': {'region': 'Addis Ababa'},
    }));
    await tester.pumpAndSettle();
    expect(find.text('Addis Ababa'), findsOneWidget);
  });

  testWidgets('a very long value no longer crashes the summary (found while testing: unbounded ListTile.trailing)',
      (tester) async {
    await tester.pumpWidget(_completedCase(_api(), {
      'location': {'postal_code': 'n' * 400},
    }));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('n' * 400), findsOneWidget);
  });
}
