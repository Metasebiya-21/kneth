// A pure-Dart unit test for the one genuine business decision in this
// feature (see load_flow_case_use_case.dart's doc comment) — a fake
// FlowRepository is enough, no Flutter harness needed, same as sync's and
// native_capture's domain tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/domain/load_flow_case_use_case.dart';

import '../../../support/fake_flow_repository.dart';

void main() {
  final manifest = FlowManifest(workflowId: 'f', clientId: 'c');

  test('start always fetches fresh and begins at the first stage', () async {
    final repository = FakeFlowRepository();
    final useCase = LoadFlowCaseUseCase(repository);

    final result = await useCase.start(manifest);

    expect(repository.fetchManifestCallCount, 1);
    expect(result.stageIndex, 0);
    expect(result.collectedValues, isEmpty);
  });

  test('resume returns null when nothing is saved', () async {
    final repository = FakeFlowRepository();
    final useCase = LoadFlowCaseUseCase(repository);

    final result = await useCase.resume(manifest);

    expect(result, isNull);
    expect(repository.fetchManifestCallCount, 0);
  });

  test('resume reuses a fresh saved case without fetching', () async {
    final freshManifest = ResolvedFlowManifest(
      workflowId: 'f',
      clientId: 'c',
      caseId: 'case-1',
      fetchedAt: DateTime.now(),
      stagesJson: fakeFlowStagesJson,
    );
    final savedState = FlowCaseState.initial(freshManifest).advanced({'name': 'Ada'});
    final repository = FakeFlowRepository(saved: savedState);
    final useCase = LoadFlowCaseUseCase(repository);

    final result = await useCase.resume(manifest);

    expect(result, same(savedState));
    expect(repository.fetchManifestCallCount, 0);
  });

  test('resume refreshes a stale saved case but keeps its progress', () async {
    final staleManifest = ResolvedFlowManifest(
      workflowId: 'f',
      clientId: 'c',
      caseId: 'case-1',
      fetchedAt: DateTime.now().subtract(const Duration(days: 2)),
      stagesJson: fakeFlowStagesJson,
    );
    final savedState = FlowCaseState.initial(staleManifest).advanced({'name': 'Ada'});
    final repository = FakeFlowRepository(saved: savedState);
    final useCase = LoadFlowCaseUseCase(repository);

    final result = await useCase.resume(manifest);

    expect(repository.fetchManifestCallCount, 1);
    expect(result, isNotNull);
    expect(result!.manifest.isStale, isFalse);
    // Progress from the stale save is preserved, not discarded.
    expect(result.collectedValues['stage_a'], {'name': 'Ada'});
  });

  test(
    'a stale-case refresh sends the saved case\'s own caseId, not just workflowId/clientId '
    '(the confirmed backend pins resume to caseId — see NOTES.md Phase 1)',
    () async {
      final staleManifest = ResolvedFlowManifest(
        workflowId: 'f',
        clientId: 'c',
        caseId: 'the-real-case-id',
        fetchedAt: DateTime.now().subtract(const Duration(days: 2)),
        stagesJson: fakeFlowStagesJson,
      );
      final savedState = FlowCaseState.initial(staleManifest).advanced({'name': 'Ada'});
      final repository = FakeFlowRepository(saved: savedState, caseIdToReturn: 'the-real-case-id');
      final useCase = LoadFlowCaseUseCase(repository);

      await useCase.resume(manifest);

      expect(repository.lastFetchCaseId, 'the-real-case-id');
      // workflowId/clientId are still sent too — harmless on the real
      // backend's resume path, and still what a genuine new-case fetch
      // needs.
      expect(repository.lastFetchWorkflowId, 'f');
      expect(repository.lastFetchClientId, 'c');
    },
  );

  test('start -> manifest carries a caseId -> a later resume-refresh echoes it back', () async {
    final repository = FakeFlowRepository(caseIdToReturn: 'assigned-by-backend');
    final useCase = LoadFlowCaseUseCase(repository);

    // start(): a brand-new case, no caseId sent, one assigned back.
    final started = await useCase.start(manifest);
    expect(repository.lastFetchCaseId, isNull);
    expect(started.manifest.caseId, 'assigned-by-backend');

    // Persist it, then make it look stale so resume() has to refresh.
    repository.saved = started.withRefreshedManifest(
      ResolvedFlowManifest(
        workflowId: started.manifest.workflowId,
        clientId: started.manifest.clientId,
        caseId: started.manifest.caseId,
        fetchedAt: DateTime.now().subtract(const Duration(days: 2)),
        stagesJson: started.manifest.stagesJson,
      ),
    );

    await useCase.resume(manifest);

    // The caseId the very first fetch returned is exactly what the
    // resume-refresh sent back — a real round trip, not just a value that
    // happens to be non-null.
    expect(repository.lastFetchCaseId, 'assigned-by-backend');
  });
}
