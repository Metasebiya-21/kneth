import 'package:kifiya_rendering_engine/kifiya_rendering_engine.dart' as engine;

import '../models/field_config.dart' as kneth;
import '../models/stage_config.dart';
import 'api_client.dart';

/// Translates a kneth [StageConfig] (our own JSON-driven field model) into
/// the [engine.FormSchema] the kifiya_rendering_engine plugin renders.
///
/// This is where the two field models' differences get reconciled:
/// - The plugin's dropdowns only take a static `List<String>`, so DYNAMIC
///   fields are resolved through [ApiClient] up front, before the schema
///   is built — the plugin itself has no concept of a remote data source.
/// - The plugin's dropdown values *are* their display label (no separate
///   value), so we submit the option label directly.
/// - The plugin's conditional visibility (`dependsOn` + `visibleWhenEquals`)
///   only supports a single equality/contains check, unlike kneth's
///   multi-condition [kneth.ConditionalDependency]. Only that simpler shape
///   is supported here; anything richer throws, so an unsupported schema
///   fails loudly instead of silently rendering wrong.
Future<engine.FormSchema> buildFormSchema({
  required StageConfig stage,
  required ApiClient apiClient,
}) async {
  final sortedFields = [...stage.fields]
    ..sort((a, b) => a.property.order.compareTo(b.property.order));

  final fieldSchemas = <engine.FieldSchema>[];
  for (final field in sortedFields) {
    // A field that's unconditionally hidden (no dependency that could ever
    // reveal it) has nothing to render.
    if (field.property.isHidden && field.property.conditionalDependency == null) {
      continue;
    }
    fieldSchemas.add(await _toFieldSchema(field, apiClient));
  }

  return engine.FormSchema(
    title: stage.title,
    fields: fieldSchemas,
    // Unused by DynamicForm/FormController today (our own FlowController
    // drives stage progression and submission) — placeholders only.
    submitApiUrl: '',
    nextFormApiUrl: '',
  );
}

Future<engine.FieldSchema> _toFieldSchema(
  kneth.FieldConfig field,
  ApiClient apiClient,
) async {
  final dependency = field.property.conditionalDependency;
  String? dependsOn;
  dynamic visibleWhenEquals;
  var required = field.property.isRequired;

  if (dependency != null) {
    if (dependency.ifConditions.length != 1 ||
        dependency.ifConditions.single.op != kneth.ConditionOp.eq) {
      throw UnsupportedError(
        'Field "${field.key}": kifiya_rendering_engine only supports a '
        'single eq condition (dependsOn + visibleWhenEquals); got '
        '${dependency.ifConditions.length} condition(s).',
      );
    }
    final condition = dependency.ifConditions.single;
    dependsOn = condition.field;
    visibleWhenEquals = condition.value;
    required = dependency.then.isRequired ?? required;
  }

  var regex = field.property.regex;
  final isPhone = field.key.toLowerCase().contains('phone') ||
      field.key.toLowerCase().contains('mobile') ||
      field.label.toLowerCase().contains('phone') ||
      field.label.toLowerCase().contains('mobile') ||
      field.label.contains('ስልክ');

  if (isPhone) {
    // Allows Ethiopian formats: 09XXXXXXXX, 07XXXXXXXX, +2519XXXXXXXX, +2517XXXXXXXX, 2519XXXXXXXX, 2517XXXXXXXX, 9XXXXXXXX, 7XXXXXXXX
    regex = r'^(\+251|251|0)?[79]\d{8}$';
  }

  return engine.FieldSchema(
    id: field.key,
    type: await _toFieldType(field),
    label: field.label,
    required: required,
    options: await _resolveOptions(field, apiClient),
    dependsOn: dependsOn,
    visibleWhenEquals: visibleWhenEquals,
    regex: regex,
  );
}

Future<engine.FieldType> _toFieldType(kneth.FieldConfig field) async {
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

Future<List<String>?> _resolveOptions(
  kneth.FieldConfig field,
  ApiClient apiClient,
) async {
  if (field.type != kneth.FieldType.select) return null;

  switch (field.inputMode) {
    case kneth.FieldInputMode.dynamic_:
      final endpoint = field.property.dynamicConfig?.endpoint ?? '';
      final options = await apiClient.fetchOptions(endpoint);
      return options.map((option) => option.label).toList();
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
