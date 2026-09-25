// FlowRepositoryImpl composes two data sources: ApiClient (remote — still
// a mock standing in for a backend that doesn't exist yet, so a fake here
// tests nothing extra, same reasoning sync's data test used) and
// SharedPreferences (local — genuinely real on-device storage, same
// reasoning native_capture's data test used for path_provider). So: a
// fake ApiClient, but real SharedPreferences (via its standard mock-
// platform-channel test setup, which exercises the real encode/decode and
// key-handling logic, only the actual platform channel is swapped out).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sdui_demo/features/flow/data/flow_repository_impl.dart';
import 'package:sdui_demo/features/flow/data/stac_manifest_mapper.dart';
import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/domain/load_flow_case_use_case.dart';

import '../../../support/fake_api_client.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fetchManifest asks the Stac route and maps its response onto ResolvedFlowManifest', () async {
    final apiClient = FakeApiClient()..caseIdToIssue = 'issued-by-backend';
    final repository = FlowRepositoryImpl(apiClient: apiClient);

    final manifest = await repository.fetchManifest(workflowId: 'f', clientId: 'c');

    expect(apiClient.fetchFlowManifestStacCallCount, 1);
    expect(manifest.workflowId, 'f');
    expect(manifest.clientId, 'c');
    expect(manifest.caseId, 'issued-by-backend', reason: 'the real case_id from the response is carried through');
    expect(manifest.stages.map((s) => s.stageId), ['stage_a', 'stage_b', 'stage_c']);
    expect(manifest.stages[1].nativeHandler.name, 'photoCapture');
    expect(manifest.stages[0].fields.single.key, 'name');
    expect(manifest.stagesJson.every(stageJsonHasWidget), isTrue, reason: 'each stage keeps its Stac widget tree');
  });

  test('no case_id creates a case (null sent, real id back); a case_id resumes it (sent, same id back)', () async {
    final apiClient = FakeApiClient()..caseIdToIssue = 'new-case-1';
    final repository = FlowRepositoryImpl(apiClient: apiClient);

    final created = await repository.fetchManifest(workflowId: 'f', clientId: 'c');
    final resumed = await repository.fetchManifest(workflowId: 'f', clientId: 'c', caseId: created.caseId);

    expect(apiClient.stacCaseIdsRequested, [null, 'new-case-1']);
    expect(created.caseId, 'new-case-1');
    expect(resumed.caseId, 'new-case-1');
  });

  test('fetchedAt is stamped at fetch time, so a fresh manifest is not stale', () async {
    final manifest = await FlowRepositoryImpl(apiClient: FakeApiClient()).fetchManifest(workflowId: 'f', clientId: 'c');
    expect(manifest.isStale, isFalse);
  });

  test('the Stac widget trees are persisted with the case and come back intact', () async {
    final repository = FlowRepositoryImpl(apiClient: FakeApiClient());
    final manifest = await repository.fetchManifest(workflowId: 'f', clientId: 'c');
    await repository.saveCaseState(FlowCaseState.initial(manifest));

    final loaded = (await repository.loadSavedCaseState('f'))!;

    expect(loaded.manifest.stagesJson.map((s) => s[kStacWidgetKey]), manifest.stagesJson.map((s) => s[kStacWidgetKey]));
    expect(loaded.manifest.isStale, isFalse, reason: 'not marked for refresh: it already has its widgets');
  });

  test('state saved before the flow was built from the Stac manifest (no widgets) is marked stale, not discarded',
      () async {
    // The previous, legacy-shaped saved state: stages without a widget tree, mid-flow, with answers.
    const legacyStages = [
      {'stageId': 'stage_a', 'title': 'Stage A', 'screenType': 'GENERIC_FORM', 'fields': <Map<String, dynamic>>[]},
    ];
    final old = FlowCaseState(
      manifest: ResolvedFlowManifest(
        workflowId: 'f',
        clientId: 'c',
        caseId: 'old-case',
        fetchedAt: DateTime.now(),
        stagesJson: legacyStages,
      ),
      stageIndex: 0,
      isComplete: false,
      collectedValues: const {},
      rememberedValues: const {},
    );
    SharedPreferences.setMockInitialValues({'sdui_flow_state_f': jsonEncode(old.toJson())});
    final repository = FlowRepositoryImpl(apiClient: FakeApiClient());

    final loaded = (await repository.loadSavedCaseState('f'))!;

    expect(loaded.manifest.isStale, isTrue);
    expect(loaded.manifest.caseId, 'old-case');
    expect(loaded.stageIndex, 0);
  });

  group('through the real LoadFlowCaseUseCase (start -> resume)', () {
    test('start creates a case and resume returns it untouched while fresh', () async {
      final apiClient = FakeApiClient()..caseIdToIssue = 'case-42';
      final useCase = LoadFlowCaseUseCase(FlowRepositoryImpl(apiClient: apiClient));
      final repository = FlowRepositoryImpl(apiClient: apiClient);
      final flow = FlowManifest(workflowId: 'f', clientId: 'c');

      final started = await useCase.start(flow);
      await repository.saveCaseState(started.advanced({'name': 'Ada'}));
      final resumed = await useCase.resume(flow);

      expect(started.manifest.caseId, 'case-42');
      expect(resumed!.manifest.caseId, 'case-42');
      expect(resumed.collectedValues['stage_a'], {'name': 'Ada'});
      expect(apiClient.fetchFlowManifestStacCallCount, 1, reason: 'a fresh saved case is not re-fetched');
    });

    test('a stale saved case is refreshed by its OWN case_id, keeping stage and answers (the hard-won resume logic)',
        () async {
      final apiClient = FakeApiClient()..caseIdToIssue = 'case-42';
      final repository = FlowRepositoryImpl(apiClient: apiClient);
      final flow = FlowManifest(workflowId: 'f', clientId: 'c');
      final fresh = await repository.fetchManifest(workflowId: 'f', clientId: 'c');
      final stale = FlowCaseState.initial(ResolvedFlowManifest(
        workflowId: 'f',
        clientId: 'c',
        caseId: fresh.caseId,
        fetchedAt: DateTime.now().subtract(const Duration(hours: 25)),
        stagesJson: fresh.stagesJson,
      )).advanced({'name': 'Ada'});
      await repository.saveCaseState(stale);
      apiClient.stacCaseIdsRequested.clear();

      final resumed = await LoadFlowCaseUseCase(repository).resume(flow);

      expect(apiClient.stacCaseIdsRequested, ['case-42'], reason: 'refresh sends the saved case_id, not a new-case request');
      expect(resumed!.manifest.isStale, isFalse);
      expect(resumed.stageIndex, 1, reason: 'the agent keeps their place');
      expect(resumed.collectedValues['stage_a'], {'name': 'Ada'}, reason: 'and their answers');
    });

    test('a case saved in the legacy shape is refreshed on resume by its case_id, keeping progress', () async {
      const legacyStages = [
        {'stageId': 'stage_a', 'title': 'Stage A', 'screenType': 'GENERIC_FORM', 'fields': <Map<String, dynamic>>[]},
        {'stageId': 'stage_b', 'title': 'Stage B', 'screenType': 'NATIVE_CAPTURE', 'nativeHandler': 'photo_capture', 'fields': <Map<String, dynamic>>[]},
      ];
      final old = FlowCaseState.initial(ResolvedFlowManifest(
        workflowId: 'f',
        clientId: 'c',
        caseId: 'old-case',
        fetchedAt: DateTime.now(),
        stagesJson: legacyStages,
      )).advanced({'anything': 'typed'});
      SharedPreferences.setMockInitialValues({'sdui_flow_state_f': jsonEncode(old.toJson())});
      final apiClient = FakeApiClient();

      final resumed = await LoadFlowCaseUseCase(FlowRepositoryImpl(apiClient: apiClient))
          .resume(FlowManifest(workflowId: 'f', clientId: 'c'));

      expect(apiClient.stacCaseIdsRequested, ['old-case']);
      expect(resumed!.manifest.stagesJson.every(stageJsonHasWidget), isTrue);
      expect(resumed.stageIndex, 1);
      expect(resumed.collectedValues['stage_a'], {'anything': 'typed'});
    });
  });

  test('loadSavedCaseState returns null when nothing was ever saved', () async {
    final repository = FlowRepositoryImpl(apiClient: FakeApiClient());

    expect(await repository.loadSavedCaseState('f'), isNull);
  });

  test('saveCaseState then loadSavedCaseState round-trips through real SharedPreferences', () async {
    final apiClient = FakeApiClient();
    final repository = FlowRepositoryImpl(apiClient: apiClient);
    final manifest = await repository.fetchManifest(workflowId: 'f', clientId: 'c');
    final state = FlowCaseState.initial(manifest).advanced({'name': 'Ada'});

    await repository.saveCaseState(state);
    final loaded = await repository.loadSavedCaseState('f');

    expect(loaded, isNotNull);
    expect(loaded!.stageIndex, state.stageIndex);
    expect(loaded.collectedValues, state.collectedValues);
    expect(loaded.manifest.workflowId, state.manifest.workflowId);
  });

  test('clearSavedCaseState removes what was saved', () async {
    final apiClient = FakeApiClient();
    final repository = FlowRepositoryImpl(apiClient: apiClient);
    final manifest = await repository.fetchManifest(workflowId: 'f', clientId: 'c');
    await repository.saveCaseState(FlowCaseState.initial(manifest));

    await repository.clearSavedCaseState('f');

    expect(await repository.loadSavedCaseState('f'), isNull);
  });

  test('different workflowIds are stored under different keys', () async {
    final apiClient = FakeApiClient();
    final repository = FlowRepositoryImpl(apiClient: apiClient);
    final manifestA = await repository.fetchManifest(workflowId: 'flow_a', clientId: 'c');
    await repository.fetchManifest(workflowId: 'flow_b', clientId: 'c');

    await repository.saveCaseState(FlowCaseState.initial(manifestA));

    expect(await repository.loadSavedCaseState('flow_a'), isNotNull);
    expect(await repository.loadSavedCaseState('flow_b'), isNull);
  });

  test('Amharic and emoji collected values survive save -> load through real SharedPreferences, exactly', () async {
    final repository = FlowRepositoryImpl(apiClient: FakeApiClient());
    final manifest = await repository.fetchManifest(workflowId: 'f', clientId: 'c');
    const values = {'name': 'አበበ በቀለ', 'note': 'ሰላም 😀 e\u0301cole'};
    final state = FlowCaseState.initial(manifest).advanced(values);

    await repository.saveCaseState(state);
    final restored = await repository.loadSavedCaseState('f');

    expect(restored!.collectedValues['stage_a'], values);
    expect(restored.collectedValues['stage_a']!['name'].toString().codeUnits, 'አበበ በቀለ'.codeUnits);
  });
}
