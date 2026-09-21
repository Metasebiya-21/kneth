import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/data/rendering_engine_adapter.dart';
import 'package:sdui_demo/features/flow/domain/stage_config.dart';

// A field whose visibility depends on TWO AND-ed clauses — a shape
// kifiya_rendering_engine's own dependsOn/visibleWhenEquals can't express,
// since it only understands a single equality check.
const Map<String, dynamic> _stageJson = {
  'stageId': 'stage_x',
  'title': 'Stage X',
  'screenType': 'GENERIC_FORM',
  'fields': [
    {
      'key': 'country',
      'label': 'Country',
      'type': 'SELECT',
      'inputMode': 'ENUM',
      'property': {
        'order': 1,
        'isRequired': true,
        'isHidden': false,
        'options': [
          {'label': 'Ethiopia', 'value': 'ET'},
          {'label': 'Kenya', 'value': 'KE'},
        ],
      },
    },
    {
      'key': 'association_type',
      'label': 'Association type',
      'type': 'SELECT',
      'inputMode': 'ENUM',
      'property': {
        'order': 2,
        'isRequired': true,
        'isHidden': false,
        'options': [
          {'label': 'Individual', 'value': 'Individual'},
          {'label': 'Group', 'value': 'Group'},
        ],
      },
    },
    {
      'key': 'company_registration_number',
      'label': 'Company registration number',
      'type': 'TEXT',
      'inputMode': 'FREE',
      'property': {
        'order': 3,
        'isRequired': false,
        'isHidden': true,
        'conditionalDependency': {
          'if': [
            {'field': 'country', 'op': 'eq', 'value': 'ET'},
            {'field': 'association_type', 'op': 'eq', 'value': 'Group'},
          ],
          'then': {'isRequired': true, 'isHidden': false},
          'else': {'isRequired': false, 'isHidden': true},
        },
      },
    },
  ],
};

void main() {
  test('a multi-clause conditionalDependency resolves through the full render path without throwing', () {
    final stage = StageConfig.fromJson(_stageJson);

    final allFieldSchemas = buildStageFieldSchemas(stage: stage);

    expect(allFieldSchemas.map((s) => s.id), contains('company_registration_number'));
  });

  test('visibility requires every AND-ed clause to match, and flips when either one changes', () {
    final stage = StageConfig.fromJson(_stageJson);
    final allFieldSchemas = buildStageFieldSchemas(stage: stage);

    List<String> visibleIds(Map<String, dynamic> values) => visibleFieldSchemasFor(
          stage: stage,
          allFieldSchemas: allFieldSchemas,
          values: values,
        ).map((s) => s.id).toList();

    // Neither clause satisfied.
    expect(visibleIds(const {}), isNot(contains('company_registration_number')));
    // Only one of the two clauses satisfied.
    expect(visibleIds(const {'country': 'ET'}), isNot(contains('company_registration_number')));
    expect(
      visibleIds(const {'association_type': 'Group'}),
      isNot(contains('company_registration_number')),
    );
    // Both clauses satisfied.
    expect(
      visibleIds(const {'country': 'ET', 'association_type': 'Group'}),
      contains('company_registration_number'),
    );
    // Flipping just one of the two AND-ed clauses back off hides it again.
    expect(
      visibleIds(const {'country': 'KE', 'association_type': 'Group'}),
      isNot(contains('company_registration_number')),
    );

    final resolved = visibleFieldSchemasFor(
      stage: stage,
      allFieldSchemas: allFieldSchemas,
      values: const {'country': 'ET', 'association_type': 'Group'},
    );
    final companyField = resolved.firstWhere((s) => s.id == 'company_registration_number');
    expect(companyField.required, isTrue);
    // The plugin is never handed a condition to interpret itself — every
    // field we pass it is unconditionally visible from its point of view.
    expect(companyField.dependsOn, isNull);
    expect(companyField.visibleWhenEquals, isNull);
  });
}
