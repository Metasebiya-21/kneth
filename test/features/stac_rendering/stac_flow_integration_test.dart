// The Stac path wired into the real FlowScreen/FlowNotifier, using
// the recorded real-backend manifests for both routes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sdui_demo/features/flow/data/flow_repository_impl.dart';
import 'package:sdui_demo/features/flow/data/stac_manifest_mapper.dart';
import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/presentation/flow_notifier.dart';
import 'package:sdui_demo/features/flow/presentation/flow_screen.dart';
import 'package:sdui_demo/features/stac_rendering/presentation/stac_flow_stage_screen.dart';
import 'package:sdui_demo/features/sync/domain/document_kind_mapping.dart';
import 'package:sdui_demo/services/api_dtos.dart';
import 'package:sdui_demo/services/app_exception.dart';

import '../../support/fake_api_client.dart';
import '../../support/fake_flow_repository.dart';
import '../../support/stac_fixtures.dart';
import 'stac_test_actions.dart';
import 'stac_test_harness.dart';

/// The flow's stages exactly as production builds them from the Stac manifest.
List<Map<String, dynamic>> _stageJson() =>
    stacStagesToStageJson((recordedStacManifest()['stages'] as List).cast<Map<String, dynamic>>());

FakeApiClient _api() =>
    FakeApiClient()..stacStages = (recordedStacManifest()['stages'] as List).cast<Map<String, dynamic>>();

Widget _app(
  FakeApiClient api, {
  required int startAtStage,
  FakeMediaStorageRepository? media,
}) {
  final manifest = ResolvedFlowManifest(
    workflowId: 'w',
    clientId: 'c',
    caseId: 'case-1',
    fetchedAt: DateTime.now(),
    stagesJson: _stageJson(),
  );
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      flowRepositoryProvider.overrideWithValue(FakeFlowRepository(
        saved: FlowCaseState(manifest: manifest, stageIndex: startAtStage, isComplete: false, collectedValues: const {}),
      )),
      if (media != null) stacMediaRepositoryProvider.overrideWithValue(media),
      stacPickPhotoProvider.overrideWithValue(() async => '/cache/picked.jpg'),
    ],
    child: MaterialApp(home: FlowScreen(manifest: FlowManifest(workflowId: 'w', clientId: 'c'), resumeMode: true)),
  );
}

FlowCaseState _state(WidgetTester tester) =>
    (ProviderScope.containerOf(tester.element(find.byType(FlowScreen))).read(flowNotifierProvider) as FlowViewReady)
        .caseState;

void main() {
  testWidgets('a captured photo lands at "<stageId>.filePath" — the key SyncScreen/SyncRepositoryImpl upload from',
      (tester) async {
    final media = FakeMediaStorageRepository();
    await tester.pumpWidget(_app(_api(), startAtStage: 1, media: media));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);

    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await tapContinue(tester);

    final values = _state(tester).allValues;
    expect(values, {'identification_card.filePath': '/fake/captures/identification_card_1.jpg'});
    // SyncScreen derives uploads from keys ending '.filePath'; the stage id
    // before it must map to a real document kind.
    final stageId = values.keys.single.substring(0, values.keys.single.length - '.filePath'.length);
    expect(documentKindForStageId(stageId), 'identification_card');
  });

  testWidgets(
      'a BUSINESS document stage (real serializer output: NATIVE_CAPTURE/photo_capture, key trade_license) renders '
      'through the same kneth_photo_capture and lands at "trade_license.filePath", targeting the business record',
      (tester) async {
    final stages = _stageJson();
    final businessIndex = stages.indexWhere((s) => s['stageId'] == 'trade_license');
    expect(businessIndex, isNonNegative, reason: 'seeded by tool/seed_stac_business_docs.sql, recorded from the real backend');
    expect(stages[businessIndex]['nativeHandler'], 'photo_capture');

    final media = FakeMediaStorageRepository();
    await tester.pumpWidget(_app(_api(), startAtStage: businessIndex, media: media));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);

    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await tapContinue(tester);

    final values = _state(tester).allValues;
    expect(values, {'trade_license.filePath': '/fake/captures/trade_license_1.jpg'});
    expect(documentTargetForStageId('trade_license'), const DocumentTarget('trade_license', DocumentOwner.business));
  });

  testWidgets('a resumed case renders every stage from its own persisted manifest: no manifest request at all',
      (tester) async {
    final api = _api();
    await tester.pumpWidget(_app(api, startAtStage: 2));
    await tester.pumpAndSettle();
    expect(find.text('association_type'), findsWidgets);
    await tapContinue(tester); // association_details -> location (also Stac)
    expect(find.text('postal_code'), findsWidgets);

    expect(api.fetchFlowManifestStacCallCount, 0, reason: 'widget trees were saved with the case');
  });

  testWidgets('starting a case makes exactly ONE manifest request (the Stac route), and every stage renders from it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _api()..caseIdToIssue = 'new-case-7';
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        flowRepositoryProvider.overrideWithValue(FlowRepositoryImpl(apiClient: api)),
      ],
      child: MaterialApp(home: FlowScreen(manifest: FlowManifest(workflowId: 'w', clientId: 'c'))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsOneWidget, reason: 'first stage (personal_info) rendered from the Stac tree');
    await tapContinue(tester); // personal_info -> identification_card (photo)
    expect(find.text('Take photo'), findsOneWidget);

    expect(api.stacCaseIdsRequested, [null], reason: 'one request, asking for a NEW case');
    expect(_state(tester).manifest.caseId, 'new-case-7', reason: 'the case_id the backend issued');
  });

  testWidgets('a failed manifest fetch shows the shared AppErrorView, and Retry starts the case', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var fail = true;
    final api = _FlakyStacApi(() => fail);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        flowRepositoryProvider.overrideWithValue(FlowRepositoryImpl(apiClient: api)),
      ],
      child: MaterialApp(home: FlowScreen(manifest: FlowManifest(workflowId: 'w', clientId: 'c'))),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('You appear to be offline'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('a stage whose manifest entry has no widget definition says so instead of showing a blank screen',
      (tester) async {
    final manifest = ResolvedFlowManifest(
      workflowId: 'w',
      clientId: 'c',
      caseId: 'case-1',
      fetchedAt: DateTime.now(),
      stagesJson: const [
        {'stageId': 'a', 'title': 'a', 'screenType': 'GENERIC_FORM', 'fields': <Map<String, dynamic>>[]},
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(FakeApiClient()),
        flowRepositoryProvider.overrideWithValue(FakeFlowRepository(
          saved: FlowCaseState(manifest: manifest, stageIndex: 0, isComplete: false, collectedValues: const {}),
        )),
      ],
      child: MaterialApp(home: FlowScreen(manifest: FlowManifest(workflowId: 'w', clientId: 'c'), resumeMode: true)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining("Stage 'a' has no widget definition"), findsOneWidget);
  });
}

class _FlakyStacApi extends FakeApiClient {
  _FlakyStacApi(this._fail) {
    stacStages = (recordedStacManifest()['stages'] as List).cast<Map<String, dynamic>>();
  }

  final bool Function() _fail;

  @override
  Future<StacFlowManifestDto> fetchFlowManifestStac({required String flowId, required String clientId, String? caseId}) async {
    if (_fail()) throw const NetworkException();
    return super.fetchFlowManifestStac(flowId: flowId, clientId: clientId, caseId: caseId);
  }
}
