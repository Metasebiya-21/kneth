import 'package:sdui_demo/features/flow/presentation/flow_session.dart';
import 'package:sdui_demo/services/api_client.dart';

/// A plain fake implementing [FlowSession] — no Riverpod, no flow
/// internals — for sync's and native_capture's own widget tests, which
/// only need flow's narrow cross-feature surface (see flow_session.dart),
/// not flow itself. Mirrors how those features already fake
/// `SyncRepository`/`MediaStorageRepository` for the same reason.
class FakeFlowSession implements FlowSession {
  FakeFlowSession({
    required this.apiClient,
    this.allValues = const {},
    this.progressLabel = 'Step 01',
    this.caseId = 'fake-case-id',
  });

  @override
  final ApiClient apiClient;

  @override
  final Map<String, dynamic> allValues;

  @override
  final String progressLabel;

  @override
  final String caseId;

  final List<Map<String, dynamic>> submittedStages = [];
  int clearSavedCallCount = 0;

  @override
  void submitStage(Map<String, dynamic> values) {
    submittedStages.add(values);
  }

  @override
  Future<void> clearSaved() async {
    clearSavedCallCount++;
  }
}
