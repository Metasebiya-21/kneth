// Exercises FlowNotifier through a plain ProviderContainer — no widgets,
// no testWidgets, so none of the fake-clock/initState gotchas documented
// in NOTES.md apply here; those only matter once a widget tree is
// involved (see flow_screen_test.dart for the one test that does need
// them).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/presentation/flow_notifier.dart';

import '../../../support/fake_flow_repository.dart';

ProviderContainer _containerWith(FakeFlowRepository repository) {
  final container = ProviderContainer(
    overrides: [flowRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final manifest = FlowManifest(workflowId: 'f', clientId: 'c');

  test('start fetches once and becomes ready at the first stage', () async {
    final repository = FakeFlowRepository();
    final container = _containerWith(repository);
    final notifier = container.read(flowNotifierProvider.notifier);

    expect(container.read(flowNotifierProvider), isA<FlowViewLoading>());

    await notifier.start(manifest);

    final state = container.read(flowNotifierProvider);
    expect(state, isA<FlowViewReady>());
    expect((state as FlowViewReady).caseState.stageIndex, 0);
    expect(repository.fetchManifestCallCount, 1);
    // A known-good state gets persisted immediately.
    expect(repository.lastSaved, state.caseState);
  });

  test('submitStage advances locally and saves, without re-fetching', () async {
    final repository = FakeFlowRepository();
    final container = _containerWith(repository);
    final notifier = container.read(flowNotifierProvider.notifier);
    await notifier.start(manifest);

    notifier.submitStage({'name': 'Ada'});

    final state = container.read(flowNotifierProvider) as FlowViewReady;
    expect(state.caseState.isComplete, isTrue); // fakeFlowStagesJson has one stage
    expect(repository.fetchManifestCallCount, 1);
    expect(repository.lastSaved, state.caseState);
  });

  test('back rewinds the in-memory state', () async {
    final repository = FakeFlowRepository(stagesJson: const [
      {'stageId': 'stage_a', 'title': 'A', 'screenType': 'GENERIC_FORM', 'fields': <Map<String, dynamic>>[]},
      {'stageId': 'stage_b', 'title': 'B', 'screenType': 'GENERIC_FORM', 'fields': <Map<String, dynamic>>[]},
    ]);
    final container = _containerWith(repository);
    final notifier = container.read(flowNotifierProvider.notifier);
    await notifier.start(manifest);
    notifier.submitStage({'name': 'Ada'});

    notifier.back();

    final state = container.read(flowNotifierProvider) as FlowViewReady;
    expect(state.caseState.stageIndex, 0);
    expect(state.caseState.currentStage.stageId, 'stage_a');
  });

  test('resume adopts a saved case without fetching when it is fresh', () async {
    final repository = FakeFlowRepository();
    // Seed a saved case the same way a previous session would have left it.
    final freshManifest = await repository.fetchManifest(workflowId: 'f', clientId: 'c');
    repository.saved = FlowCaseState.initial(freshManifest).advanced({'name': 'Ada'});
    repository.fetchManifestCallCount = 0;

    final container = _containerWith(repository);
    final notifier = container.read(flowNotifierProvider.notifier);

    await notifier.resume(manifest);

    expect(repository.fetchManifestCallCount, 0);
    final state = container.read(flowNotifierProvider);
    expect(state, isA<FlowViewReady>());
    expect((state as FlowViewReady).caseState.collectedValues['stage_a'], {'name': 'Ada'});
  });

  test('a failed start reports FlowViewError, and retry re-attempts it', () async {
    final repository = FakeFlowRepository()..fetchManifestError = Exception('offline');
    final container = _containerWith(repository);
    final notifier = container.read(flowNotifierProvider.notifier);

    await notifier.start(manifest);
    expect(container.read(flowNotifierProvider), isA<FlowViewError>());

    repository.fetchManifestError = null;
    await notifier.retry();

    expect(container.read(flowNotifierProvider), isA<FlowViewReady>());
  });

  test('clearSaved clears the repository for this manifest', () async {
    final repository = FakeFlowRepository();
    final container = _containerWith(repository);
    final notifier = container.read(flowNotifierProvider.notifier);
    await notifier.start(manifest);

    await notifier.clearSaved();

    expect(repository.clearSavedCallCount, 1);
  });
}
