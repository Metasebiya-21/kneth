import 'package:flutter_riverpod/legacy.dart';

import '../../../services/api_client.dart';
import '../../../services/app_exception.dart';
import '../domain/dynamic_options.dart';
import '../domain/field_config.dart';
import '../domain/stage_config.dart';

/// One DYNAMIC field's current options-fetch status. Same sealed-class
/// idiom as sync's `SyncStatus` (idle/uploading/succeeded/failed there;
/// not-ready/loading/ready/failed here) — but this one lives in
/// presentation/, not domain/: unlike `SyncStatus`, which describes real,
/// meaningful states of a case upload, this describes "is this screen's
/// current network fetch for this field done yet" — an artifact of one
/// screen session's async operation, the same reason flow's own
/// `FlowViewState` lives in presentation/ rather than domain/.
sealed class DynamicFieldOptionsStatus {
  const DynamicFieldOptionsStatus();
}

/// Not all of this field's dependencies have a value yet — nothing to
/// fetch, so there's nothing to show.
class DynamicFieldOptionsNotReady extends DynamicFieldOptionsStatus {
  const DynamicFieldOptionsNotReady();
}

class DynamicFieldOptionsLoading extends DynamicFieldOptionsStatus {
  const DynamicFieldOptionsLoading();
}

class DynamicFieldOptionsReady extends DynamicFieldOptionsStatus {
  /// The options as label/value pairs: a dropdown shows the label and stores
  /// the real [FieldOption.value].
  final List<FieldOption> fieldOptions;

  const DynamicFieldOptionsReady(this.fieldOptions);
}

class DynamicFieldOptionsFailed extends DynamicFieldOptionsStatus {
  final AppException error;
  const DynamicFieldOptionsFailed(this.error);
}

/// Owns the reactive fetch/re-fetch lifecycle for every DYNAMIC field in
/// one stage: hooks into the exact same "recompute on every value change"
/// point `FieldConfig.effectiveState` already uses (the Stac dropdown
/// parser calls [sync] whenever the stage's values change), rather than a second, parallel
/// change-detection path — [sync] is what that recomputation calls.
///
/// [sync] compares each DYNAMIC field's resolved dependency values (see
/// [changedDynamicFieldKeys]) against what they resolved to last time it
/// was called: unchanged fields are left alone entirely, changed ones get
/// a fresh fetch kicked off (or reset to "not ready" if the change was a
/// dependency becoming un-filled), and their keys are returned so the
/// caller can clear that field's own now-possibly-invalid selection —
/// clearing and re-fetching always happen together, never one without the
/// other, so the UI never shows a selection that isn't in the current
/// options list.
///
/// [clientId]/[workflowId] identify which manifest a field's live options
/// are resolved against — the confirmed route needs both (see
/// NOTES.md's Phase 3); the Stac dropdown scope sources them from
/// the current `FlowCaseState.manifest`, the already-resolved,
/// resume-accurate source, not the original `FlowManifest` input.
class DynamicOptionsController extends StateNotifier<Map<String, DynamicFieldOptionsStatus>> {
  final ApiClient apiClient;
  final StageConfig stage;
  final String clientId;
  final String workflowId;

  /// Told about every successful fetch, so a later screen can display a
  /// stored value's label without re-fetching (`resolvedOptionsProvider`).
  final void Function(String fieldKey, List<FieldOption> options)? onOptionsResolved;

  Map<String, dynamic> _lastValues = const {};
  bool _hasSyncedOnce = false;

  DynamicOptionsController({
    required this.apiClient,
    required this.stage,
    required this.clientId,
    required this.workflowId,
    this.onOptionsResolved,
  }) : super({});

  /// Call once when the stage first loads, and again every time the
  /// stage's form values change. Returns the field keys whose own value
  /// should now be cleared — empty on the very first call, since nothing
  /// has been selected yet for there to be anything stale to clear.
  Set<String> sync(Map<String, dynamic> values) {
    final isFirstSync = !_hasSyncedOnce;
    // On the first sync there's no "previous" to diff against — every
    // DYNAMIC field needs its initial status established (ready or not),
    // not just the ones that happen to differ from an empty baseline
    // (which would wrongly skip a field that's *still* not ready, e.g.
    // region genuinely has no value yet).
    final changed = isFirstSync
        ? {
            for (final field in stage.fields)
              if (field.inputMode == FieldInputMode.dynamic_) field.key,
          }
        : changedDynamicFieldKeys(stage: stage, previousValues: _lastValues, newValues: values);

    _hasSyncedOnce = true;
    _lastValues = values;

    for (final fieldKey in changed) {
      final field = _fieldByKey(fieldKey);
      if (field == null) continue;
      final resolved = resolveDependencyValues(field.property.dependsOn, values);
      if (resolved == null) {
        state = {...state, fieldKey: const DynamicFieldOptionsNotReady()};
      } else {
        _fetch(fieldKey, resolved);
      }
    }

    return isFirstSync ? const {} : changed;
  }

  /// Re-attempts a failed fetch for [fieldKey], using whatever values it
  /// last resolved against.
  void retry(String fieldKey) {
    final field = _fieldByKey(fieldKey);
    if (field == null) return;
    final resolved = resolveDependencyValues(field.property.dependsOn, _lastValues);
    if (resolved == null) return;
    _fetch(fieldKey, resolved);
  }

  FieldConfig? _fieldByKey(String key) {
    for (final field in stage.fields) {
      if (field.key == key) return field;
    }
    return null;
  }

  Future<void> _fetch(String fieldKey, Map<String, String> dependencyValues) async {
    state = {...state, fieldKey: const DynamicFieldOptionsLoading()};
    try {
      final options = await apiClient.fetchOptions(
        clientId: clientId,
        workflowId: workflowId,
        fieldKey: fieldKey,
        dependencyValues: dependencyValues,
      );
      final fieldOptions = options.map((o) => FieldOption(label: o.label, value: o.value)).toList();
      onOptionsResolved?.call(fieldKey, fieldOptions);
      state = {
        ...state,
        fieldKey: DynamicFieldOptionsReady(fieldOptions),
      };
    } on AppException catch (e) {
      state = {...state, fieldKey: DynamicFieldOptionsFailed(e)};
    } catch (e) {
      state = {...state, fieldKey: DynamicFieldOptionsFailed(UnknownException(e.toString()))};
    }
  }
}
