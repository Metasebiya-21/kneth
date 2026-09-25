import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/field_config.dart';
import 'package:sdui_demo/features/flow/domain/hidden_field_values.dart';

FieldConfig _field(String key, {bool hidden = false, Map<String, dynamic>? conditional}) => FieldConfig(
      key: key,
      label: key,
      type: FieldType.text,
      inputMode: FieldInputMode.free,
      property: FieldProperty.fromJson({
        'isRequired': false,
        'isHidden': hidden,
        if (conditional != null) 'conditionalDependency': conditional,
      }),
    );

const _groupOnly = {
  'if': [
    {'field': 'kind', 'op': 'eq', 'value': 'Group'},
  ],
  'then': {'isHidden': false},
  'else': {'isHidden': true},
};

void main() {
  final company = _field('company', hidden: true, conditional: _groupOnly);

  test('a conditional field that is hidden NOW is removed outright (key absent, not null or blank)', () {
    final result = dropHiddenFieldValues([company], {'kind': 'Individual', 'company': 'Acme'});
    expect(result, {'kind': 'Individual'});
    expect(result.containsKey('company'), isFalse);
  });

  test('the same field visible NOW keeps its value (only current visibility matters)', () {
    expect(dropHiddenFieldValues([company], {'kind': 'Group', 'company': 'Acme'}), {'kind': 'Group', 'company': 'Acme'});
  });

  test('a field with a hidden base and no condition is dropped (e.g. a prefill for an always-hidden field)', () {
    expect(dropHiddenFieldValues([_field('secret', hidden: true)], {'secret': 'seed', 'x': 1}), {'x': 1});
  });

  test('keys that are not a listed field (e.g. filePath) and explicit nulls of visible fields are untouched', () {
    final result = dropHiddenFieldValues([company], {'kind': 'Group', 'company': null, 'filePath': '/a.png'});
    expect(result, {'kind': 'Group', 'company': null, 'filePath': '/a.png'});
  });

  test('no hidden fields: an equal copy, and the input is never mutated', () {
    final input = {'a': 1};
    final result = dropHiddenFieldValues([_field('a')], input);
    expect(result, input);
    expect(identical(result, input), isFalse);
    dropHiddenFieldValues([company], {'kind': 'Individual', 'company': 'x'});
  });

  test('partitionHiddenFieldValues splits sent from remembered, and kept equals dropHiddenFieldValues', () {
    final values = {'kind': 'Individual', 'company': 'Acme', 'filePath': '/a.png'};
    final parts = partitionHiddenFieldValues([company], values);
    expect(parts.kept, {'kind': 'Individual', 'filePath': '/a.png'});
    expect(parts.dropped, {'company': 'Acme'});
    expect(parts.kept, dropHiddenFieldValues([company], values));

    final visible = partitionHiddenFieldValues([company], {'kind': 'Group', 'company': 'Acme'});
    expect(visible.dropped, isEmpty);
  });
}
