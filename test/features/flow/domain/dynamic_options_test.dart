import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/dynamic_options.dart';
import 'package:sdui_demo/features/flow/domain/field_config.dart';
import 'package:sdui_demo/features/flow/domain/stage_config.dart';

void main() {
  group('resolveDependencyValues', () {
    test('no dependencies at all is always ready, with an empty map', () {
      expect(resolveDependencyValues(const [], const {}), <String, String>{});
    });

    test('a single dependency present in values resolves it', () {
      expect(
        resolveDependencyValues(const ['region'], const {'region': 'addis_ababa'}),
        {'region': 'addis_ababa'},
      );
    });

    test('stringifies a non-string value', () {
      expect(resolveDependencyValues(const ['region'], const {'region': 42}), {'region': '42'});
    });

    test('returns null when a named dependency is missing', () {
      expect(resolveDependencyValues(const ['region'], const {}), isNull);
    });

    test('returns null when only one of several dependencies is missing', () {
      expect(resolveDependencyValues(const ['region', 'district'], const {'region': 'oromia'}), isNull);
    });

    test('resolves multiple dependencies', () {
      expect(
        resolveDependencyValues(const ['region', 'district'], const {'region': 'oromia', 'district': 'adama'}),
        {'region': 'oromia', 'district': 'adama'},
      );
    });
  });

  group('changedDynamicFieldKeys', () {
    final stage = StageConfig(
      stageId: 's',
      title: 'S',
      screenType: ScreenType.genericForm,
      fields: [
        FieldConfig(
          key: 'region',
          label: 'Region',
          type: FieldType.select,
          inputMode: FieldInputMode.enumMode,
          property: FieldProperty(order: 1, isRequired: true, isHidden: false),
        ),
        FieldConfig(
          key: 'district',
          label: 'District',
          type: FieldType.select,
          inputMode: FieldInputMode.dynamic_,
          property: FieldProperty(
            order: 2,
            isRequired: true,
            isHidden: false,
            dependsOn: const ['region'],
            dynamicConfig: DynamicConfig(endpoint: '/options/regions/{region}/districts', method: 'GET'),
          ),
        ),
      ],
    );

    test('a dependency going from unset to set counts as changed', () {
      final changed = changedDynamicFieldKeys(
        stage: stage,
        previousValues: const {},
        newValues: const {'region': 'addis_ababa'},
      );
      expect(changed, {'district'});
    });

    test('a dependency changing from one value to another counts as changed', () {
      final changed = changedDynamicFieldKeys(
        stage: stage,
        previousValues: const {'region': 'addis_ababa'},
        newValues: const {'region': 'oromia'},
      );
      expect(changed, {'district'});
    });

    test('an unrelated field changing does not flag district', () {
      final changed = changedDynamicFieldKeys(
        stage: stage,
        previousValues: const {'region': 'addis_ababa', 'unrelated': 'x'},
        newValues: const {'region': 'addis_ababa', 'unrelated': 'y'},
      );
      expect(changed, isEmpty);
    });

    test('no change at all reports nothing', () {
      final changed = changedDynamicFieldKeys(
        stage: stage,
        previousValues: const {'region': 'addis_ababa'},
        newValues: const {'region': 'addis_ababa'},
      );
      expect(changed, isEmpty);
    });
  });
}
