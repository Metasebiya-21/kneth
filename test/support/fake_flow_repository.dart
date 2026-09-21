import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/domain/flow_repository.dart';

const List<Map<String, dynamic>> fakeFlowStagesJson = [
  {
    'stageId': 'stage_a',
    'title': 'Stage A',
    'screenType': 'GENERIC_FORM',
    'fields': <Map<String, dynamic>>[],
  },
];

/// A plain, in-memory fake — no network, no SharedPreferences — for
/// exercising [LoadFlowCaseUseCase] and [FlowNotifier] without needing a
/// real [FlowRepositoryImpl].
class FakeFlowRepository implements FlowRepository {
  FakeFlowRepository({
    this.saved,
    DateTime? fetchedManifestAt,
    this.stagesJson = fakeFlowStagesJson,
    this.caseIdToReturn = 'fake-case-id',
  }) : fetchedManifestAt = fetchedManifestAt ?? DateTime.now();

  FlowCaseState? saved;
  final DateTime fetchedManifestAt;
  final List<Map<String, dynamic>> stagesJson;

  /// The `caseId` every [fetchManifest] call returns, unless the call
  /// itself passed one in (a resume-refresh), in which case that one is
  /// echoed back instead — same as a real backend pinning resume to the
  /// case that was asked for.
  final String caseIdToReturn;

  int fetchManifestCallCount = 0;
  FlowCaseState? lastSaved;
  int clearSavedCallCount = 0;

  /// What the most recent [fetchManifest] call was actually given — lets a
  /// test assert *which* parameters a resume-refresh sent (e.g. that it
  /// carried the saved case's own `caseId`), not just that a call happened.
  String? lastFetchWorkflowId;
  String? lastFetchClientId;
  String? lastFetchCaseId;

  Object? fetchManifestError;

  @override
  Future<ResolvedFlowManifest> fetchManifest({
    required String workflowId,
    required String clientId,
    String? caseId,
  }) async {
    fetchManifestCallCount++;
    lastFetchWorkflowId = workflowId;
    lastFetchClientId = clientId;
    lastFetchCaseId = caseId;
    final error = fetchManifestError;
    if (error != null) throw error;
    return ResolvedFlowManifest(
      workflowId: workflowId,
      clientId: clientId,
      caseId: caseId ?? caseIdToReturn,
      fetchedAt: fetchedManifestAt,
      stagesJson: stagesJson,
    );
  }

  @override
  Future<FlowCaseState?> loadSavedCaseState(String workflowId) async => saved;

  @override
  Future<void> saveCaseState(FlowCaseState state) async {
    lastSaved = state;
    saved = state;
  }

  @override
  Future<void> clearSavedCaseState(String workflowId) async {
    clearSavedCallCount++;
    saved = null;
  }
}
