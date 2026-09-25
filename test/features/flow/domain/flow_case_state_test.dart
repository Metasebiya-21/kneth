import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';

const List<Map<String, dynamic>> _twoStages = [
  {
    'stageId': 'stage_a',
    'title': 'Stage A',
    'screenType': 'GENERIC_FORM',
    'fields': <Map<String, dynamic>>[],
  },
  {
    'stageId': 'stage_b',
    'title': 'Stage B',
    'screenType': 'GENERIC_FORM',
    'fields': <Map<String, dynamic>>[
      {
        'key': 'note',
        'label': 'Note',
        'type': 'TEXT',
        'inputMode': 'FREE',
        'prefill': 'carried over',
        'property': {'order': 1, 'isRequired': false, 'isHidden': false},
      },
    ],
  },
];

ResolvedFlowManifest _manifest({List<Map<String, dynamic>> stages = _twoStages, DateTime? fetchedAt}) {
  return ResolvedFlowManifest(
    workflowId: 'f',
    clientId: 'c',
    caseId: 'case-1',
    fetchedAt: fetchedAt ?? DateTime.now(),
    stagesJson: stages,
  );
}

void main() {
  test('initial state starts at the first stage', () {
    final state = FlowCaseState.initial(_manifest());

    expect(state.stageIndex, 0);
    expect(state.isComplete, isFalse);
    expect(state.currentStage.stageId, 'stage_a');
  });

  test('initial state of an empty manifest is immediately complete', () {
    final state = FlowCaseState.initial(_manifest(stages: const []));

    expect(state.isComplete, isTrue);
  });

  test('advanced records values and moves to the next stage', () {
    final state = FlowCaseState.initial(_manifest());

    final next = state.advanced({'name': 'Ada'});

    expect(next.stageIndex, 1);
    expect(next.isComplete, isFalse);
    expect(next.currentStage.stageId, 'stage_b');
    expect(next.collectedValues['stage_a'], {'name': 'Ada'});
    // The original state is untouched — advanced() is pure.
    expect(state.stageIndex, 0);
  });

  test('advancing past the last stage marks the case complete', () {
    final state = FlowCaseState.initial(_manifest()).advanced({'name': 'Ada'});

    final done = state.advanced({'note': 'ok'});

    expect(done.isComplete, isTrue);
  });

  test('advanced is a no-op once the case is already complete', () {
    final done = FlowCaseState.initial(_manifest())
        .advanced({'name': 'Ada'})
        .advanced({'note': 'ok'});

    final stillDone = done.advanced({'ignored': true});

    expect(stillDone.collectedValues, done.collectedValues);
    expect(stillDone.isComplete, isTrue);
  });

  test('rewound returns to the previous stage without losing collected values', () {
    final state = FlowCaseState.initial(_manifest()).advanced({'name': 'Ada'});

    final back = state.rewound();

    expect(back.stageIndex, 0);
    expect(back.isComplete, isFalse);
    // Going back doesn't discard what was already submitted.
    expect(back.collectedValues['stage_a'], {'name': 'Ada'});
  });

  test('rewound is a no-op at the first stage', () {
    final state = FlowCaseState.initial(_manifest());

    expect(state.rewound().stageIndex, 0);
  });

  test('valuesForStage falls back to that stage\'s prefill when nothing is collected yet', () {
    final state = FlowCaseState.initial(_manifest());

    expect(state.valuesForStage('stage_b'), {'note': 'carried over'});
    expect(state.valuesForStage('stage_a'), <String, dynamic>{});
  });

  test('valuesForStage prefers already-collected values over prefill', () {
    final state = FlowCaseState.initial(_manifest()).advanced({'name': 'Ada'});
    final onStageB = state.advanced({'note': 'agent-entered'});

    expect(onStageB.valuesForStage('stage_b'), {'note': 'agent-entered'});
  });

  test('allValues flattens collected values as stageId.field keys', () {
    final state = FlowCaseState.initial(_manifest())
        .advanced({'name': 'Ada'})
        .advanced({'note': 'ok'});

    expect(state.allValues, {
      'stage_a.name': 'Ada',
      'stage_b.note': 'ok',
    });
  });

  test('withRefreshedManifest keeps progress and values, re-derives isComplete', () {
    final state = FlowCaseState.initial(_manifest()).advanced({'name': 'Ada'});
    final refreshed = _manifest(); // same two stages, new fetchedAt

    final result = state.withRefreshedManifest(refreshed);

    expect(result.manifest, same(refreshed));
    expect(result.stageIndex, 1);
    expect(result.collectedValues['stage_a'], {'name': 'Ada'});
    expect(result.isComplete, isFalse);
  });

  test('withRefreshedManifest marks complete if the new manifest has fewer stages', () {
    final state = FlowCaseState.initial(_manifest()).advanced({'name': 'Ada'}); // stageIndex 1
    final shorter = _manifest(stages: const [
      {
        'stageId': 'stage_a',
        'title': 'Stage A',
        'screenType': 'GENERIC_FORM',
        'fields': <Map<String, dynamic>>[],
      },
    ]);

    final result = state.withRefreshedManifest(shorter);

    expect(result.isComplete, isTrue);
  });

  test('toJson/fromJson round-trips a case state', () {
    final state = FlowCaseState.initial(_manifest(fetchedAt: DateTime(2026, 1, 1)))
        .advanced({'name': 'Ada'});

    final restored = FlowCaseState.fromJson(state.toJson());

    expect(restored.stageIndex, state.stageIndex);
    expect(restored.isComplete, state.isComplete);
    expect(restored.collectedValues, state.collectedValues);
    expect(restored.manifest.workflowId, state.manifest.workflowId);
    expect(restored.manifest.caseId, state.manifest.caseId);
  });

  group('remembered values (hidden at submit; Phase 3, section 14.4)', () {
    FlowCaseState submitted() =>
        FlowCaseState.initial(_manifest()).advanced({'kind': 'Individual'}, remembered: {'company': 'Acme'});

    test('are kept beside, never inside, what is collected and sent', () {
      final state = submitted();
      expect(state.collectedValues['stage_a'], {'kind': 'Individual'});
      expect(state.allValues, {'stage_a.kind': 'Individual'});
      expect(state.allValues.containsKey('stage_a.company'), isFalse);
    });

    test('reappear when the stage is shown again (valuesForStage), collected values winning any overlap', () {
      final state = submitted();
      expect(state.valuesForStage('stage_a'), {'company': 'Acme', 'kind': 'Individual'});
      final overlap = FlowCaseState.initial(_manifest()).advanced({'x': 'new'}, remembered: {'x': 'old', 'y': 'y'});
      expect(overlap.valuesForStage('stage_a'), {'x': 'new', 'y': 'y'});
    });

    test('a stage with nothing remembered behaves exactly as before, prefill included', () {
      final state = FlowCaseState.initial(_manifest());
      expect(state.rememberedValues, isEmpty);
      expect(state.valuesForStage('stage_b'), {'note': 'carried over'});
      expect(state.valuesForStage('stage_a'), isEmpty);
    });

    test('resubmitting the stage replaces what was remembered, and empty remembered clears it', () {
      final again = submitted().rewound().advanced({'kind': 'Group', 'company': 'Acme'});
      expect(again.rememberedValues, isEmpty);
      expect(again.allValues['stage_a.company'], 'Acme');
    });

    test('survive rewound() and a manifest refresh', () {
      final state = FlowCaseState.initial(_manifest()).advanced({'a': 1}, remembered: {'h': 2}).advanced({}).rewound();
      expect(state.rememberedValues['stage_a'], {'h': 2});
      expect(state.withRefreshedManifest(_manifest()).rememberedValues['stage_a'], {'h': 2});
    });

    test('persist: toJson/fromJson round-trips them, and state saved before this existed still loads', () {
      final restored = FlowCaseState.fromJson(submitted().toJson());
      expect(restored.rememberedValues, {'stage_a': {'company': 'Acme'}});
      expect(restored.allValues, {'stage_a.kind': 'Individual'});

      final noneRemembered = FlowCaseState.initial(_manifest()).advanced({'a': 1});
      expect(noneRemembered.toJson().containsKey('rememberedByStage'), isFalse, reason: 'unchanged format when unused');
      final legacyJson = Map<String, dynamic>.of(noneRemembered.toJson());
      expect(FlowCaseState.fromJson(legacyJson).rememberedValues, isEmpty);
    });
  });
}
