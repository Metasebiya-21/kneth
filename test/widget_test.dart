import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/controllers/flow_controller.dart';
import 'package:sdui_demo/models/field_config.dart';
import 'package:sdui_demo/models/flow_manifest.dart';
import 'package:sdui_demo/screens/flow_screen.dart';
import 'package:sdui_demo/services/api_client.dart';

/// A single-stage flow, served the same way a real backend would: only
/// [FakeApiClient.fetchNextStage] knows this stage exists.
class FakeApiClient implements ApiClient {
  @override
  Future<Map<String, dynamic>?> fetchNextStage({
    required String flowId,
    required String? afterStageId,
    required Map<String, dynamic>? submittedValues,
  }) async {
    if (afterStageId != null) return null;
    return {
      'stageId': 'stage_one',
      'title': 'Stage One',
      'screenType': 'GENERIC_FORM',
      'fields': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<List<FieldOption>> fetchOptions(String endpoint) async => const [];

  @override
  Future<void> uploadCaseData(Map<String, dynamic> values) async {}

  @override
  Future<void> uploadMedia(List<String> filePaths) async {}

  @override
  Future<void> finalizeCase() async {}
}

void main() {
  testWidgets('FlowScreen renders the current stage title', (WidgetTester tester) async {
    final manifest = FlowManifest(flowId: 'test_flow');
    final controller = FlowController(manifest: manifest, apiClient: FakeApiClient());

    await tester.pumpWidget(MaterialApp(home: FlowScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('Stage One'), findsOneWidget);
  });
}
