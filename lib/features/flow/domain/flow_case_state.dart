import 'flow_manifest.dart';
import 'stage_config.dart';

/// A case in progress: a resolved manifest, where the agent currently is
/// in it, and whatever's been collected so far. Every transition
/// (advancing, going back, refreshing a stale manifest) is a pure
/// function from one [FlowCaseState] to the next — no I/O, no Flutter.
/// [FlowRepository] persists/restores this shape; [FlowNotifier]
/// (presentation) is the only thing that decides *when* to call these
/// methods and to save the result.
class FlowCaseState {
  final ResolvedFlowManifest manifest;
  final int stageIndex;
  final bool isComplete;
  final Map<String, Map<String, dynamic>> collectedValues;

  /// Answers a stage's fields had when it was submitted but which were hidden
  /// at that moment, so they were NOT collected (never in [allValues], never
  /// sent). Kept only so the value can reappear on screen if the agent returns
  /// to the stage and re-reveals the field; see [valuesForStage].
  final Map<String, Map<String, dynamic>> rememberedValues;

  const FlowCaseState({
    required this.manifest,
    required this.stageIndex,
    required this.isComplete,
    required this.collectedValues,
    this.rememberedValues = const {},
  });

  /// A brand-new case, positioned at the first stage (or already complete,
  /// if the manifest happens to have none).
  factory FlowCaseState.initial(ResolvedFlowManifest manifest) {
    return FlowCaseState(
      manifest: manifest,
      stageIndex: manifest.stages.isEmpty ? -1 : 0,
      isComplete: manifest.stages.isEmpty,
      collectedValues: const {},
    );
  }

  /// Only valid when [isComplete] is false.
  StageConfig get currentStage => manifest.stages[stageIndex];

  String get progressLabel => 'Step ${(stageIndex + 1).toString().padLeft(2, '0')}';

  Map<String, dynamic> get allValues => {
        for (final entry in collectedValues.entries)
          for (final value in entry.value.entries)
            '${entry.key}.${value.key}': value.value,
      };

  /// Values already submitted for [stageId], or each of that stage's
  /// fields' own backend-provided prefill if nothing has been submitted
  /// for it yet. Prefill is field-level ([FieldConfig.prefill]), not
  /// stage-level — see NOTES.md's Phase 5 — so this collects one fallback
  /// map from whichever fields actually have one, rather than reading a
  /// single stage-wide map.
  Map<String, dynamic> valuesForStage(String stageId) {
    final remembered = rememberedValues[stageId] ?? const <String, dynamic>{};
    final collected = collectedValues[stageId];
    if (collected != null) return {...remembered, ...collected};
    final stage = _stageById(stageId);
    if (stage == null) return {...remembered};
    return {
      ...remembered,
      for (final field in stage.fields)
        if (field.prefill != null) field.key: field.prefill!,
    };
  }

  StageConfig? _stageById(String stageId) {
    for (final stage in manifest.stages) {
      if (stage.stageId == stageId) return stage;
    }
    return null;
  }

  /// Records [values] for the current stage and moves to the next one (or
  /// to complete, if that was the last stage). A no-op (returns this same
  /// state) if the case is already complete or has no current stage.
  ///
  /// [remembered] is what hidden fields held at submit time (see [rememberedValues]);
  /// it is stored beside, never inside, the collected values.
  FlowCaseState advanced(Map<String, dynamic> values, {Map<String, dynamic> remembered = const {}}) {
    if (isComplete || stageIndex < 0 || stageIndex >= manifest.stages.length) {
      return this;
    }
    final stageId = currentStage.stageId;
    final nextIndex = stageIndex + 1;
    return FlowCaseState(
      manifest: manifest,
      stageIndex: nextIndex,
      isComplete: nextIndex >= manifest.stages.length,
      collectedValues: {
        ...collectedValues,
        stageId: Map<String, dynamic>.from(values),
      },
      rememberedValues: {
        for (final entry in rememberedValues.entries)
          if (entry.key != stageId) entry.key: entry.value,
        if (remembered.isNotEmpty) stageId: Map<String, dynamic>.from(remembered),
      },
    );
  }

  /// Returns to the previously-visited stage, if any. A no-op at the first
  /// stage.
  FlowCaseState rewound() {
    if (stageIndex <= 0) return this;
    return FlowCaseState(
      manifest: manifest,
      stageIndex: stageIndex - 1,
      isComplete: false,
      collectedValues: collectedValues,
      rememberedValues: rememberedValues,
    );
  }

  /// The manifest had gone stale and has just been re-fetched — keeps the
  /// agent's progress and already-collected values, pointed at the new
  /// manifest, with [isComplete] re-derived against its (possibly
  /// different) stage count.
  FlowCaseState withRefreshedManifest(ResolvedFlowManifest refreshed) {
    return FlowCaseState(
      manifest: refreshed,
      stageIndex: stageIndex,
      isComplete: stageIndex >= refreshed.stages.length,
      collectedValues: collectedValues,
      rememberedValues: rememberedValues,
    );
  }

  factory FlowCaseState.fromJson(Map<String, dynamic> json) {
    final rawValues = json['valuesByStage'] as Map<String, dynamic>? ?? {};
    return FlowCaseState(
      manifest: ResolvedFlowManifest.fromJson(json['manifest'] as Map<String, dynamic>),
      stageIndex: json['stageIndex'] as int? ?? 0,
      isComplete: json['isComplete'] as bool? ?? false,
      collectedValues: {
        for (final entry in rawValues.entries)
          entry.key: Map<String, dynamic>.from(entry.value as Map),
      },
      rememberedValues: {
        for (final entry in (json['rememberedByStage'] as Map<String, dynamic>? ?? const {}).entries)
          entry.key: Map<String, dynamic>.from(entry.value as Map),
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'manifest': manifest.toJson(),
        'stageIndex': stageIndex,
        'isComplete': isComplete,
        'valuesByStage': collectedValues,
        if (rememberedValues.isNotEmpty) 'rememberedByStage': rememberedValues,
      };
}
