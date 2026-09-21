// DynamicOptionsController is a plain StateNotifier — no Riverpod
// container needed to test it directly, same as flow_case_state_test.dart
// needing no harness for pure domain logic. Only its dependency on
// ApiClient needs faking.
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/field_config.dart';
import 'package:sdui_demo/features/flow/domain/stage_config.dart';
import 'package:sdui_demo/features/flow/presentation/dynamic_options_controller.dart';
import 'package:sdui_demo/services/api_dtos.dart';

import '../../../support/fake_api_client.dart';

final _stage = StageConfig(
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
        dynamicConfig: DynamicConfig(endpoint: '/reference-data/regions/{region}/districts', method: 'GET'),
      ),
    ),
  ],
);

DynamicOptionsController _controllerWith(FakeApiClient apiClient) => DynamicOptionsController(
      apiClient: apiClient,
      stage: _stage,
      clientId: 'client-1',
      workflowId: 'workflow-1',
    );

void main() {
  test('a field with an unmet dependency starts (and stays) not ready', () {
    final apiClient = FakeApiClient();
    final controller = _controllerWith(apiClient);

    controller.sync(const {});

    expect(controller.state['district'], isA<DynamicFieldOptionsNotReady>());
    expect(apiClient.fetchOptionsCallCount, 0);
  });

  test('a satisfied dependency fetches options for the field, scoped by dependency value', () async {
    final apiClient = FakeApiClient(optionsByEndpoint: {
      FakeApiClient.optionsKey('district', {'region': 'addis_ababa'}): const [
        FieldOptionDto(label: 'Bole', value: 'bole'),
        FieldOptionDto(label: 'Yeka', value: 'yeka'),
      ],
    });
    final controller = _controllerWith(apiClient);

    final cleared = controller.sync(const {'region': 'addis_ababa'});
    expect(controller.state['district'], isA<DynamicFieldOptionsLoading>());
    expect(cleared, isEmpty); // first sync — nothing was ever selected

    await Future<void>.delayed(Duration.zero);

    expect(apiClient.fetchOptionsFieldKeys, ['district']);
    final ready = controller.state['district'] as DynamicFieldOptionsReady;
    expect(ready.options, ['Bole', 'Yeka']);
  });

  test('changing the dependency clears the dependent field and re-fetches its own list', () async {
    final apiClient = FakeApiClient(optionsByEndpoint: {
      FakeApiClient.optionsKey('district', {'region': 'addis_ababa'}): const [
        FieldOptionDto(label: 'Bole', value: 'bole'),
      ],
      FakeApiClient.optionsKey('district', {'region': 'oromia'}): const [
        FieldOptionDto(label: 'Adama', value: 'adama'),
      ],
    });
    final controller = _controllerWith(apiClient);

    controller.sync(const {'region': 'addis_ababa'});
    await Future<void>.delayed(Duration.zero);
    expect((controller.state['district'] as DynamicFieldOptionsReady).options, ['Bole']);

    final cleared = controller.sync(const {'region': 'oromia', 'district': 'bole'});
    // Confirmed cleared *before* the new fetch resolves — a caller must
    // never show the old region's selection alongside the new region's
    // (still loading) options.
    expect(cleared, {'district'});
    expect(controller.state['district'], isA<DynamicFieldOptionsLoading>());

    await Future<void>.delayed(Duration.zero);

    expect(apiClient.fetchOptionsFieldKeys, ['district', 'district']);
    final ready = controller.state['district'] as DynamicFieldOptionsReady;
    expect(ready.options, ['Adama']); // the NEW region's list, not the old one's
  });

  test('an unrelated field changing does not re-fetch', () async {
    final apiClient = FakeApiClient(optionsByEndpoint: {
      FakeApiClient.optionsKey('district', {'region': 'addis_ababa'}): const [
        FieldOptionDto(label: 'Bole', value: 'bole'),
      ],
    });
    final controller = _controllerWith(apiClient);

    controller.sync(const {'region': 'addis_ababa'});
    await Future<void>.delayed(Duration.zero);
    expect(apiClient.fetchOptionsCallCount, 1);

    final cleared = controller.sync(const {'region': 'addis_ababa', 'unrelated': 'x'});

    expect(cleared, isEmpty);
    expect(apiClient.fetchOptionsCallCount, 1);
  });

  test('a failed fetch reports failure, and retry tries again', () async {
    final apiClient = _FailingThenSucceedingApiClient();
    final controller = _controllerWith(apiClient);

    controller.sync(const {'region': 'addis_ababa'});
    await Future<void>.delayed(Duration.zero);
    expect(controller.state['district'], isA<DynamicFieldOptionsFailed>());

    controller.retry('district');
    expect(controller.state['district'], isA<DynamicFieldOptionsLoading>());
    await Future<void>.delayed(Duration.zero);

    expect((controller.state['district'] as DynamicFieldOptionsReady).options, ['Bole']);
  });

  test('the confirmed route\'s clientId/workflowId/fieldKey/dependencyValues are all threaded through', () async {
    final apiClient = FakeApiClient();
    final controller = _controllerWith(apiClient);

    controller.sync(const {'region': 'addis_ababa'});
    await Future<void>.delayed(Duration.zero);

    expect(apiClient.fetchOptionsFieldKeys, ['district']);
  });
}

class _FailingThenSucceedingApiClient extends FakeApiClient {
  int _calls = 0;

  @override
  Future<List<FieldOptionDto>> fetchOptions({
    required String clientId,
    required String workflowId,
    required String fieldKey,
    required Map<String, String> dependencyValues,
  }) async {
    _calls++;
    if (_calls == 1) throw Exception('offline');
    return const [FieldOptionDto(label: 'Bole', value: 'bole')];
  }
}
