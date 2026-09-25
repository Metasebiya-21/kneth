import 'field_config.dart';

/// [values] without the entries of any field in [fields] that is hidden
/// *right now*: `FieldConfig.effectiveState` (the existing
/// `ConditionalDependency.resolve` logic) evaluated against [values] as they
/// stand at submit time — not against any earlier moment. A field that was
/// hidden, then shown, then filled in is visible now and keeps its value; a
/// field that was filled in and then hidden again is dropped. The key is
/// removed outright (not blanked, not nulled).
///
/// Keys that aren't a listed field's key (e.g. a native-capture stage's
/// `filePath`) are left alone, and so are explicit `null`s of visible fields
/// (a cleared dependent dropdown keeps its `null`, as before).
///
/// Used by `StacStageScreen`, at the single point it hands its collected
/// values to `FlowNotifier.submitStage`. Before this existed the previous
/// renderer and the Stac path both submitted
/// the whole form-values map, hidden fields' stale values included
/// (STAC_MIGRATION_SCOPING.md 12.5). Pure, no I/O.
Map<String, dynamic> dropHiddenFieldValues(List<FieldConfig> fields, Map<String, dynamic> values) =>
    partitionHiddenFieldValues(fields, values).kept;

/// [values] split into what is sent ([kept]) and what a currently-hidden
/// field had ([dropped]). Dropping happens at submit time; [dropped] is not
/// discarded but handed to `FlowCaseState.advanced(remembered:)` so the answer
/// can be *shown* again if the agent comes back and re-reveals the field. Sending
/// and remembering are separate concerns: a field can remember what was typed
/// without that value being sent while hidden (STAC_MIGRATION_SCOPING.md 14.4).
({Map<String, dynamic> kept, Map<String, dynamic> dropped}) partitionHiddenFieldValues(
  List<FieldConfig> fields,
  Map<String, dynamic> values,
) {
  final hiddenKeys = <String>{
    for (final field in fields)
      if (field.effectiveState(values).isHidden) field.key,
  };
  return (
    kept: {
      for (final entry in values.entries)
        if (!hiddenKeys.contains(entry.key)) entry.key: entry.value,
    },
    dropped: {
      for (final entry in values.entries)
        if (hiddenKeys.contains(entry.key)) entry.key: entry.value,
    },
  );
}
