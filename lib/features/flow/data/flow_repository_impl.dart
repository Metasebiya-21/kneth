import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_client.dart';
import '../domain/flow_case_state.dart';
import '../domain/flow_manifest.dart';
import '../domain/flow_repository.dart';
import 'stac_manifest_mapper.dart';

/// The real implementation of [FlowRepository] — the only file in this
/// feature that touches [ApiClient] (remote) or [SharedPreferences]
/// (local) directly, and the only one that knows a persisted case is
/// stored as a JSON string under a `sdui_flow_state_<workflowId>` key.
/// Both dependencies are genuinely real, same as native_capture's
/// `MediaStorageRepositoryImpl` — `ApiClient` is still a mock standing in
/// for a backend that doesn't exist yet (see its own TODOs), but
/// `SharedPreferences` is real on-device storage today.
///
/// Also the one file in this feature that turns the wire manifest into flow's domain types:
/// [ApiClient.fetchFlowManifestStac]'s `StacFlowManifestDto` becomes a [ResolvedFlowManifest] via
/// `stac_manifest_mapper.dart`. [ApiClient] still names its own parameter `flowId` even though every
/// name in this file is `workflowId` (see NOTES.md's Phase 5 for why that mismatch wasn't renamed).
class FlowRepositoryImpl implements FlowRepository {
  final ApiClient apiClient;

  const FlowRepositoryImpl({required this.apiClient});

  String _storageKey(String workflowId) => 'sdui_flow_state_$workflowId';

  @override
  Future<ResolvedFlowManifest> fetchManifest({
    required String workflowId,
    required String clientId,
    String? caseId,
  }) async {
    // The one manifest route the app uses: POST /cases/flow-manifest/stac. No case_id creates a
    // case (the response carries its real case_id); a case_id resumes that case's frozen stages.
    final dto = await apiClient.fetchFlowManifestStac(flowId: workflowId, clientId: clientId, caseId: caseId);
    return ResolvedFlowManifest(
      workflowId: workflowId,
      clientId: clientId,
      caseId: dto.caseId,
      // Stamped here (never a wire field), as it always was.
      fetchedAt: DateTime.now(),
      stagesJson: stacStagesToStageJson(dto.stages),
    );
  }

  @override
  Future<FlowCaseState?> loadSavedCaseState(String workflowId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(workflowId));
    if (raw == null) return null;
    final saved = FlowCaseState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return _refreshIfSavedBeforeStacManifest(saved);
  }

  /// State saved before the flow was built from the Stac manifest holds stages without their
  /// widget tree, which the screens now need. Rather than discard an in-progress case, its
  /// manifest is marked stale (fetched "at the epoch"), so `LoadFlowCaseUseCase.resume` re-fetches
  /// it by case id, exactly as for any stale manifest, keeping the agent's stage and answers.
  FlowCaseState _refreshIfSavedBeforeStacManifest(FlowCaseState saved) {
    final stages = saved.manifest.stagesJson;
    if (stages.every(stageJsonHasWidget)) return saved;
    final m = saved.manifest;
    return FlowCaseState(
      manifest: ResolvedFlowManifest(
        workflowId: m.workflowId,
        clientId: m.clientId,
        caseId: m.caseId,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
        stagesJson: m.stagesJson,
      ),
      stageIndex: saved.stageIndex,
      isComplete: saved.isComplete,
      collectedValues: saved.collectedValues,
      rememberedValues: saved.rememberedValues,
    );
  }

  @override
  Future<void> saveCaseState(FlowCaseState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey(state.manifest.workflowId),
      jsonEncode(state.toJson()),
    );
  }

  @override
  Future<void> clearSavedCaseState(String workflowId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey(workflowId));
  }
}
