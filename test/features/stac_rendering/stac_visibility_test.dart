import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/hidden_field_values.dart';
import 'package:sdui_demo/features/stac_rendering/presentation/stac_visibility.dart';

import '../../support/stac_fixtures.dart';

void main() {
  test('finds the conditional envelope and the statically hidden field in a stage tree', () {
    final fields = visibilityFieldsIn({
      'type': 'column',
      'children': [
        {'type': 'kneth_text', 'id': 'always', 'label': 'always'},
        {
          'type': 'kneth_conditional',
          'property': {
            'isHidden': true,
            'conditionalDependency': {
              'if': [
                {'field': 'a', 'op': 'eq', 'value': 'x'},
              ],
              'then': {'isHidden': false},
              'else': {'isHidden': true},
            },
          },
          'child': {'type': 'kneth_text', 'id': 'cond', 'label': 'cond'},
        },
        {
          'type': 'visibility',
          'visible': false,
          'child': {'type': 'kneth_text', 'id': 'static_hidden', 'label': 'static_hidden'},
        },
        {
          'type': 'visibility',
          'visible': true,
          'child': {'type': 'kneth_text', 'id': 'shown', 'label': 'shown'},
        },
      ],
    });

    expect(fields.map((f) => f.key), ['cond', 'static_hidden']);
    expect(dropHiddenFieldValues(fields, {'a': 'y', 'cond': 1, 'static_hidden': 2, 'shown': 3, 'always': 4}),
        {'a': 'y', 'shown': 3, 'always': 4});
    expect(dropHiddenFieldValues(fields, {'a': 'x', 'cond': 1, 'static_hidden': 2}), {'a': 'x', 'cond': 1});
  });

  test('the real recorded association stage yields exactly company_name', () {
    expect(visibilityFieldsIn(recordedStacWidget('association_details')).map((f) => f.key), ['company_name']);
  });

  test('a stage with nothing conditional yields nothing', () {
    expect(visibilityFieldsIn(recordedStacWidget('personal_info')), isEmpty);
    expect(visibilityFieldsIn(recordedStacWidget('identification_card')), isEmpty);
  });
}
