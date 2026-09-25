/// Translates the Stac manifest (`POST /cases/flow-manifest/stac`, STAC_MIGRATION_SCOPING.md
/// section 11) into the stage descriptors the flow domain already uses, so the flow's state
/// can be built from the one route the app talks to, with no change to `ResolvedFlowManifest`,
/// `StageConfig`, `FieldConfig`, `FlowCaseState` or anything downstream.
///
/// A mapped stage is the domain's existing stage JSON (`stageId`, `title`, `screenType`,
/// `nativeHandler`, `fields`) **plus** the stage's Stac `widget` tree under the extra key
/// `widget`. `StageConfig.fromJson` ignores unknown keys, and `ResolvedFlowManifest` persists
/// `stagesJson` wholesale, so the widget tree the screen renders is saved with the case and
/// resume works offline without a second request.
///
/// What flow actually reads from a manifest [verified: grep of `lib/`]: per stage `stageId`,
/// `title`, `screenType`, `nativeHandler`; per field (only via the completion summary and the
/// prefill fallback) `key`, `type`, `inputMode`, `property.options`, `property.dependsOn`, and
/// `prefill`. All of it is derivable from the Stac tree; the one exception, `prefill`, is a
/// constant `null` on the backend (`router.py` hard-codes `prefill=None` and no domain object
/// carries it), so nothing is lost. Field *ordering* is tree order (the backend already sorts
/// by `order`), not key order as in the legacy response; nothing depends on it.
///
/// Equivalence with the legacy response was checked on real recorded data, field by field, in
/// `stac_manifest_mapper_test.dart`.
library;

const String kStacWidgetKey = 'widget';

/// Maps every stage of a Stac manifest, in order.
List<Map<String, dynamic>> stacStagesToStageJson(List<Map<String, dynamic>> stacStages) =>
    [for (final stage in stacStages) stacStageToStageJson(stage)];

Map<String, dynamic> stacStageToStageJson(Map<String, dynamic> stage) {
  final widget = (stage['widget'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  return {
    'stageId': stage['stageId'],
    'title': stage['title'],
    'screenType': stage['screenType'],
    'nativeHandler': stage['nativeHandler'],
    'fields': _fieldsIn(widget),
    kStacWidgetKey: widget,
  };
}

/// Whether a stage JSON already carries its Stac widget tree (state saved before the flow
/// was built from the Stac manifest does not).
bool stageJsonHasWidget(Map<String, dynamic> stageJson) => stageJson[kStacWidgetKey] is Map;

List<Map<String, dynamic>> _fieldsIn(Map<String, dynamic> widget) {
  final fields = <Map<String, dynamic>>[];

  void walk(dynamic node, {required bool hidden}) {
    if (node is List) {
      for (final child in node) {
        walk(child, hidden: hidden);
      }
      return;
    }
    if (node is! Map) return;
    final type = node['type'];

    if (type == 'kneth_conditional') {
      final envelope = node.cast<String, dynamic>();
      final child = (envelope['child'] as Map).cast<String, dynamic>();
      fields.add(_field(child,
          property: (envelope['property'] as Map).cast<String, dynamic>(), forceHidden: hidden));
      return;
    }
    if (type is String && _isFieldType(type)) {
      fields.add(_field(node.cast<String, dynamic>(), forceHidden: hidden));
      return;
    }
    final nowHidden = hidden || (type == 'visibility' && node['visible'] == false);
    for (final value in node.values) {
      walk(value, hidden: nowHidden);
    }
  }

  walk(widget, hidden: false);
  return fields;
}

bool _isFieldType(String type) =>
    type == 'kneth_text' || type == 'kneth_date' || type == 'kneth_dropdown' || type == 'kneth_unsupported_field';

Map<String, dynamic> _field(Map<String, dynamic> node, {Map<String, dynamic>? property, required bool forceHidden}) {
  final type = node['type'] as String;
  final id = node['id'] as String;

  final (fieldType, inputMode) = switch (type) {
    'kneth_text' => ('TEXT', 'FREE'),
    'kneth_date' => ('TEXT', 'DATE'),
    'kneth_dropdown' => ('SELECT', node['dynamicConfig'] != null ? 'DYNAMIC' : 'ENUM'),
    // the backend's marker for a combination it couldn't map: it carries the raw strings
    _ => (node['fieldType'] as String? ?? 'UNKNOWN', node['inputMode'] as String? ?? 'UNKNOWN'),
  };

  return {
    'key': id,
    'label': node['label'] ?? id,
    'type': fieldType,
    'inputMode': inputMode,
    'property': {
      'order': node['order'] ?? 0,
      'isRequired': property?['isRequired'] ?? node['required'] ?? false,
      'isHidden': forceHidden || (property?['isHidden'] ?? false),
      'minLen': node['minLen'],
      'maxLen': node['maxLen'],
      'regex': node['regex'],
      'options': node['options'],
      'dynamicConfig': node['dynamicConfig'],
      'dependsOn': property?['dependsOn'] ?? node['dependsOn'] ?? const <String>[],
      'conditionalDependency': property?['conditionalDependency'],
    },
    'prefill': null,
    'consentRequired': node['consentRequired'] ?? false,
  };
}
