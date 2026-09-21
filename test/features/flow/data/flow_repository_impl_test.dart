// FlowRepositoryImpl composes two data sources: ApiClient (remote — still
// a mock standing in for a backend that doesn't exist yet, so a fake here
// tests nothing extra, same reasoning sync's data test used) and
// SharedPreferences (local — genuinely real on-device storage, same
// reasoning native_capture's data test used for path_provider). So: a
// fake ApiClient, but real SharedPreferences (via its standard mock-
// platform-channel test setup, which exercises the real encode/decode and
// key-handling logic, only the actual platform channel is swapped out).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sdui_demo/features/flow/data/flow_repository_impl.dart';
import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';

import '../../../support/fake_api_client.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fetchManifest delegates to ApiClient and maps its DTO onto ResolvedFlowManifest', () async {
    final apiClient = FakeApiClient();
    final repository = FlowRepositoryImpl(apiClient: apiClient);

    final manifest = await repository.fetchManifest(workflowId: 'f', clientId: 'c');

    expect(apiClient.fetchFlowManifestCallCount, 1);
    // ApiClient itself returns a FlowManifestDto (see api_dtos.dart) —
    // this confirms FlowRepositoryImpl's private mapping carried every
    // field across onto the domain type, not just some of them.
    expect(manifest.workflowId, 'f');
    expect(manifest.clientId, 'c');
    expect(manifest.stagesJson, FakeApiClient.defaultStagesJson);
    expect(manifest.stages.map((s) => s.stageId), ['stage_a', 'stage_b', 'stage_c']);
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
}
