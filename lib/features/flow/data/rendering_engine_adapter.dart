import 'package:kifiya_rendering_engine/kifiya_rendering_engine.dart' as engine;

import '../domain/field_config.dart' as kneth;
import '../domain/stage_config.dart';

/// Translates a kneth [StageConfig] (our own JSON-driven field model) into
/// the [engine.FieldSchema]s the kifiya_rendering_engine plugin renders.
///
/// This lives in data/, not domain/: it depends on a real third-party
/// Flutter plugin (kifiya_rendering_engine), which makes it infrastructure
/// in the same sense as native_capture's `MediaStorageRepositoryImpl`
/// wrapping path_provider — a real external dependency the app's own
/// business logic shouldn't have to know about. (The boundary script backs
/// this up mechanically: this file imports
/// `package:kifiya_rendering_engine/...`, which the domain-only allowlist
/// would reject outright if this were ever moved there by mistake.) It
/// isn't wrapped behind its own abstract port the way
/// `FlowRepository`/`MediaStorageRepository` are, because nothing needs to
/// substitute a different rendering engine at runtime — the two functions
/// below are already directly testable as plain functions.
///
/// Building a stage's fields is split into two steps because visibility
/// and required-ness can depend on other fields' values, which change as
/// the agent types:
///
/// - [buildStageFieldSchemas] resolves every field once (types, ENUM
///   options) into the plugin's shape, unfiltered — call this when the
///   stage is loaded. DYNAMIC fields start with empty options here: unlike
///   ENUM's options (fixed at schema-build time) or effectiveState's
///   visibility (recomputed from values already in hand), a DYNAMIC
///   field's valid options depend on a network call that only makes sense
///   to run once its dependencies actually have values, and needs to
///   re-run every time those values change — see
///   `DynamicOptionsController` (presentation/), which owns that reactive
///   fetch/re-fetch/clear-on-change lifecycle and overlays its live
///   results onto the schema this function returns.
/// - [visibleFieldSchemasFor] is pure and synchronous: given those resolved
///   schemas and the stage's current form values, it returns only the
///   fields that should currently render, with `required` set to their
///   resolved value — call this on every value change (see
///   RenderingEngineStageScreen).
///
/// kneth's own [kneth.FieldConfig.effectiveState] (built on
/// [kneth.ConditionalDependency.resolve], domain/ logic) is the single
/// source of truth for visibility/required, for every condition shape
/// including multi-clause "if" arrays. The plugin's own
/// dependsOn/visibleWhenEquals interpreter — which only understands a
/// single equality/contains check — is never used: every
/// [engine.FieldSchema] handed to it leaves dependsOn unset, so the plugin
/// treats every field it's given as unconditionally visible and simply
/// renders whatever `required` we computed.
///
/// The plugin's dropdown values *are* their display label (no separate
/// value), so we submit the option label directly.
List<engine.FieldSchema> buildStageFieldSchemas({required StageConfig stage}) {
  final sortedFields = [...stage.fields]
    ..sort((a, b) => a.property.order.compareTo(b.property.order));

  final fieldSchemas = <engine.FieldSchema>[];
  for (final field in sortedFields) {
    // A field that's unconditionally hidden (no dependency that could ever
    // reveal it) has nothing to render.
    if (field.property.isHidden && field.property.conditionalDependency == null) {
      continue;
    }
    fieldSchemas.add(_toFieldSchema(field));
  }
  return fieldSchemas;
}

/// Filters [allFieldSchemas] (from [buildStageFieldSchemas]) down to the
/// fields that should currently render for [stage] given [values], with
/// each field's `required` resolved for those same values.
List<engine.FieldSchema> visibleFieldSchemasFor({
  required StageConfig stage,
  required List<engine.FieldSchema> allFieldSchemas,
  required Map<String, dynamic> values,
}) {
  final fieldsByKey = {for (final field in stage.fields) field.key: field};
  final resolved = <engine.FieldSchema>[];
  for (final schema in allFieldSchemas) {
    final field = fieldsByKey[schema.id];
    // No matching kneth field config (shouldn't happen) — render as-is.
    if (field == null) {
      resolved.add(schema);
      continue;
    }
    final state = field.effectiveState(values);
    if (state.isHidden) continue;
    resolved.add(schema.copyWith(required: state.isRequired));
  }
  return resolved;
}

engine.FieldSchema _toFieldSchema(kneth.FieldConfig field) {
  return engine.FieldSchema(
    id: field.key,
    type: _toFieldType(field),
    label: field.label,
    required: field.property.isRequired,
    options: _staticOptions(field),
    regex: field.property.regex,
  );
}

engine.FieldType _toFieldType(kneth.FieldConfig field) {
  switch (field.type) {
    case kneth.FieldType.text:
      return field.inputMode == kneth.FieldInputMode.date
          ? engine.FieldType.date
          : engine.FieldType.text;
    case kneth.FieldType.select:
      return engine.FieldType.dropdown;
    case kneth.FieldType.unknown:
      throw UnsupportedError('Field "${field.key}" has no supported type/inputMode.');
  }
}

/// Options known up front, with no network call — ENUM's fixed list, or
/// DYNAMIC's starting-empty placeholder (see this file's doc comment for
/// why DYNAMIC can't be resolved here).
List<String>? _staticOptions(kneth.FieldConfig field) {
  if (field.type != kneth.FieldType.select) return null;

  switch (field.inputMode) {
    case kneth.FieldInputMode.dynamic_:
      return const [];
    case kneth.FieldInputMode.enumMode:
      return (field.property.options ?? []).map((option) => option.label).toList();
    case kneth.FieldInputMode.free:
    case kneth.FieldInputMode.date:
    case kneth.FieldInputMode.unknown:
      throw UnsupportedError(
        'Field "${field.key}": SELECT field has unsupported inputMode ${field.inputMode}.',
      );
  }
}
