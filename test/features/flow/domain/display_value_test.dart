import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/display_value.dart';
import 'package:sdui_demo/features/flow/domain/field_config.dart';

void main() {
  final options = [
    FieldOption(label: 'Addis Ababa', value: '4b42dc7e'),
    FieldOption(label: 'Oromia', value: '7f1bed2a'),
  ];

  test('a stored value shows its option label', () {
    expect(displayLabelFor('4b42dc7e', options), 'Addis Ababa');
  });

  test('falls back to the raw stored value when no option matches (incl. a label stored by the old engine)', () {
    expect(displayLabelFor('unknown-id', options), 'unknown-id');
    expect(displayLabelFor('Addis Ababa', options), 'Addis Ababa');
  });

  test('falls back to the raw value when no options are known, or none exist', () {
    expect(displayLabelFor('4b42dc7e', null), '4b42dc7e');
    expect(displayLabelFor('4b42dc7e', const []), '4b42dc7e');
  });

  test('non-string values keep their previous rendering', () {
    expect(displayLabelFor(42, options), '42');
    expect(displayLabelFor(null, options), 'null');
  });
}
