import 'field_config.dart';
import 'stage_config.dart';

/// The current string value of every field [dependsOn] names, or null if
/// any of them doesn't have a value yet ("not ready to fetch"). These are
/// exactly the query parameters `ApiClient.fetchOptions` sends to the
/// confirmed live-options route.
///
/// Confirmed, not assumed (NOTES.md's Phase 3): this replaces the
/// previous `resolveDynamicEndpoint`, which built a full URL by
/// substituting `{fieldKey}` placeholders into a field's own
/// `dynamicConfig.endpoint` template. That assumed the endpoint the
/// manifest sends is literally callable — it isn't. The real backend's
/// live-options route is fixed
/// (`/config/clients/{client_id}/workflows/{workflow_id}/fields/
/// {field_key}/options`), identified by the field's own `key`, never by
/// its `dynamicConfig.endpoint` string — so there's no URL to build here
/// anymore, only a readiness check and a set of values. `dynamicConfig`
/// itself is still parsed from the manifest (the confirmed contract still
/// sends it) but is no longer read by this function or by
/// `ApiClient.fetchOptions`.
///
/// Pure, no I/O — this is what "is a DYNAMIC field's dependency
/// satisfied" reduces to, which is why it lives in domain/ rather than
/// next to the network call that eventually uses it (data/, via
/// `ApiClient.fetchOptions`).
Map<String, String>? resolveDependencyValues(List<String> dependsOn, Map<String, dynamic> values) {
  final resolved = <String, String>{};
  for (final name in dependsOn) {
    final value = values[name];
    if (value == null) return null;
    resolved[name] = value.toString();
  }
  return resolved;
}

/// Which of [stage]'s DYNAMIC fields resolve to different dependency
/// values between [previousValues] and [newValues] — these are exactly
/// the fields whose own current selection should be cleared and whose
/// options need re-fetching, because whatever they depend on changed. A
/// field going from "not ready" (null) to ready counts as changed too,
/// the same as one resolved value changing to a different one — both mean
/// "this field's set of valid options is no longer the same as it was."
///
/// Pure: two value snapshots in, a set of field keys out — no stored
/// state, no I/O. Reuses [resolveDependencyValues] rather than
/// re-deriving readiness a second way.
Set<String> changedDynamicFieldKeys({
  required StageConfig stage,
  required Map<String, dynamic> previousValues,
  required Map<String, dynamic> newValues,
}) {
  final changed = <String>{};
  for (final field in stage.fields) {
    if (field.inputMode != FieldInputMode.dynamic_) continue;
    final dependsOn = field.property.dependsOn;
    final before = resolveDependencyValues(dependsOn, previousValues);
    final after = resolveDependencyValues(dependsOn, newValues);
    if (!_dependencyValuesEqual(before, after)) changed.add(field.key);
  }
  return changed;
}

bool _dependencyValuesEqual(Map<String, String>? a, Map<String, String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
