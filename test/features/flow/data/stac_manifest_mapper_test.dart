// Phase 1 (STAC_MIGRATION_SCOPING.md section 15): the flow's state is built from the Stac
// manifest instead of the legacy one. The claim that this loses nothing is checked here on REAL
// recorded responses of both routes for the same case: for every stage and field of the legacy
// response (the reference), the mapped Stac stage carries the same information the flow domain
// reads.
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/data/stac_manifest_mapper.dart';
import 'package:sdui_demo/features/flow/domain/field_config.dart';
import 'package:sdui_demo/features/flow/domain/stage_config.dart';

import '../../../support/stac_fixtures.dart';

Map<String, Map<String, dynamic>> _byKey(dynamic fields) => {
      for (final f in (fields as List).cast<Map<String, dynamic>>()) f['key'] as String: f,
    };

void main() {
  final legacyStages = (recordedLegacyManifest()['stages'] as List).cast<Map<String, dynamic>>();
  final stacStages = (recordedStacManifest()['stages'] as List).cast<Map<String, dynamic>>();

  test('the two recorded responses describe the same case', () {
    expect(recordedStacManifest()['case_id'], isNotEmpty);
    expect(legacyStages.map((s) => s['stageId']).toSet(), stacStages.map((s) => s['stageId']).toSet());
    expect(recordedLegacyManifest()['workflow_version'], recordedStacManifest()['workflow_version']);
  });

  group('every stage and field of the real legacy response is present, equal, in the mapped Stac stage', () {
    for (final legacy in legacyStages) {
      final id = legacy['stageId'] as String;
      test('stage $id', () {
        final mapped = stacStageToStageJson(stacStages.firstWhere((s) => s['stageId'] == id));

        expect(mapped['stageId'], legacy['stageId']);
        expect(mapped['title'], legacy['title']);
        expect(mapped['screenType'], legacy['screenType']);
        expect(mapped['nativeHandler'], legacy['nativeHandler']);

        final legacyFields = _byKey(legacy['fields']);
        final mappedFields = _byKey(mapped['fields']);
        expect(mappedFields.keys.toSet(), legacyFields.keys.toSet());

        for (final key in legacyFields.keys) {
          final want = legacyFields[key]!;
          final got = mappedFields[key]!;
          for (final k in ['key', 'label', 'type', 'inputMode', 'prefill', 'consentRequired']) {
            expect(got[k], want[k], reason: '$id.$key.$k');
          }
          final wantProp = (want['property'] as Map).cast<String, dynamic>();
          final gotProp = (got['property'] as Map).cast<String, dynamic>();
          for (final k in [
            'order', 'isRequired', 'isHidden', 'minLen', 'maxLen', 'regex',
            'options', 'dynamicConfig', 'dependsOn', 'conditionalDependency',
          ]) {
            expect(gotProp[k], wantProp[k], reason: '$id.$key.property.$k');
          }
        }

        // ...and through the domain parser the flow actually uses:
        final a = StageConfig.fromJson(legacy);
        final b = StageConfig.fromJson(mapped);
        expect(b.screenType, a.screenType);
        expect(b.nativeHandler, a.nativeHandler);
        final aByKey = {for (final f in a.fields) f.key: f};
        for (final f in b.fields) {
          final g = aByKey[f.key]!;
          expect(f.type, g.type);
          expect(f.inputMode, g.inputMode);
          expect(f.property.dependsOn, g.property.dependsOn);
          expect((f.property.options ?? []).map((o) => (o.label, o.value)),
              (g.property.options ?? []).map((o) => (o.label, o.value)));
          expect(f.property.dynamicConfig?.endpoint, g.property.dynamicConfig?.endpoint);
          expect(f.effectiveState({'association_type': 'Group'}).isHidden,
              g.effectiveState({'association_type': 'Group'}).isHidden);
          expect(f.effectiveState({'association_type': 'Individual'}).isRequired,
              g.effectiveState({'association_type': 'Individual'}).isRequired);
        }
      });
    }
  });

  test('the Stac widget tree is carried verbatim next to the fields (so it persists with the case)', () {
    for (final stac in stacStages) {
      final mapped = stacStageToStageJson(stac);
      expect(mapped[kStacWidgetKey], stac['widget']);
      expect(stageJsonHasWidget(mapped), isTrue);
    }
  });

  test('a stage JSON in the previous (legacy) shape is recognized as lacking a widget', () {
    expect(stageJsonHasWidget(legacyStages.first), isFalse);
  });

  group('shapes the recorded fixtures do not contain', () {
    Map<String, dynamic> stage(Map<String, dynamic> widget) =>
        {'stageId': 's', 'title': 's', 'screenType': 'GENERIC_FORM', 'nativeHandler': null, 'widget': widget};

    test('an unconditionally hidden field (built-in visibility) is hidden', () {
      final mapped = stacStageToStageJson(stage({
        'type': 'column',
        'children': [
          {
            'type': 'visibility',
            'visible': false,
            'child': {'type': 'kneth_text', 'id': 'secret', 'label': 'secret', 'required': true, 'order': 1},
          },
        ],
      }));
      final field = (mapped['fields'] as List).single as Map;
      expect((field['property'] as Map)['isHidden'], isTrue);
      expect((field['property'] as Map)['isRequired'], isTrue);
    });

    test('the backend\'s unsupported-field marker keeps its raw type strings', () {
      final mapped = stacStageToStageJson(stage({
        'type': 'column',
        'children': [
          {'type': 'kneth_unsupported_field', 'id': 'odd', 'fieldType': 'SELECT', 'inputMode': 'FREE'},
        ],
      }));
      final field = StageConfig.fromJson(mapped).fields.single;
      expect(field.key, 'odd');
      expect(field.type, FieldType.select);
      expect(field.inputMode, FieldInputMode.free);
    });

    test('a date field and a live (DYNAMIC) dropdown map to their input modes', () {
      final mapped = stacStageToStageJson(stage({
        'type': 'column',
        'children': [
          {'type': 'kneth_date', 'id': 'd', 'label': 'd', 'required': false, 'order': 1},
          {
            'type': 'kneth_dropdown', 'id': 'district', 'label': 'district', 'required': true, 'order': 2,
            'dependsOn': ['region'], 'dynamicConfig': {'endpoint': '/x/{region}', 'method': 'GET'},
          },
        ],
      }));
      final fields = StageConfig.fromJson(mapped).fields;
      expect(fields[0].inputMode, FieldInputMode.date);
      expect(fields[1].inputMode, FieldInputMode.dynamic_);
      expect(fields[1].property.dependsOn, ['region']);
    });

    test('a native-capture stage has no fields; a stage with no widget maps to an empty tree, not a crash', () {
      final native = stacStageToStageJson({
        'stageId': 'id_card', 'title': 'id_card', 'screenType': 'NATIVE_CAPTURE', 'nativeHandler': 'photo_capture',
        'widget': {'type': 'kneth_photo_capture', 'id': 'id_card', 'label': 'id_card'},
      });
      expect(native['fields'], isEmpty);
      expect(StageConfig.fromJson(native).nativeHandler, NativeHandler.photoCapture);

      final empty = stacStageToStageJson({'stageId': 'x', 'title': 'x', 'screenType': 'GENERIC_FORM'});
      expect(empty['fields'], isEmpty);
    });
  });
}
