import '../../flow/domain/field_config.dart';

/// The [FieldConfig] a `kneth_conditional` envelope stands for: only its
/// `property` matters to `FieldConfig.effectiveState`, so type/inputMode are
/// left "unknown" rather than guessed from the child.
FieldConfig fieldConfigForConditional(Map<String, dynamic> envelope) {
  final child = (envelope['child'] as Map).cast<String, dynamic>();
  final id = child['id'] as String? ?? '';
  return FieldConfig(
    key: id,
    label: child['label'] as String? ?? id,
    type: FieldType.unknown,
    inputMode: FieldInputMode.unknown,
    property: FieldProperty.fromJson((envelope['property'] as Map).cast<String, dynamic>()),
  );
}

FieldConfig _alwaysHidden(String id) => FieldConfig(
      key: id,
      label: id,
      type: FieldType.unknown,
      inputMode: FieldInputMode.unknown,
      property: FieldProperty(order: 0, isRequired: false, isHidden: true),
    );

/// Every field in a stage's Stac JSON whose visibility can be anything other
/// than "always shown": each `kneth_conditional` envelope (resolved by the
/// existing effectiveState), and each field under a static
/// `visibility {visible: false}` (unconditionally hidden — what the backend
/// emits for a hidden field with no condition, section 11.3). What
/// `dropHiddenFieldValues` needs to know which submitted values to drop.
List<FieldConfig> visibilityFieldsIn(Map<String, dynamic> widgetJson) {
  final found = <FieldConfig>[];

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
      found.add(hidden ? _alwaysHidden(child['id'] as String? ?? '') : fieldConfigForConditional(envelope));
      return;
    }
    final nowHidden = hidden || (type == 'visibility' && node['visible'] == false);
    if (nowHidden && type is String && type.startsWith('kneth_') && node['id'] is String) {
      found.add(_alwaysHidden(node['id'] as String));
    }
    for (final value in node.values) {
      walk(value, hidden: nowHidden);
    }
  }

  walk(widgetJson, hidden: false);
  return found;
}
