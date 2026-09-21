import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_client.dart';
import '../../../services/api_dtos.dart';
import '../domain/flow_case_state.dart';
import '../domain/flow_manifest.dart';
import '../domain/flow_repository.dart';

/// The real implementation of [FlowRepository] — the only file in this
/// feature that touches [ApiClient] (remote) or [SharedPreferences]
/// (local) directly, and the only one that knows a persisted case is
/// stored as a JSON string under a `sdui_flow_state_<workflowId>` key.
/// Both dependencies are genuinely real, same as native_capture's
/// `MediaStorageRepositoryImpl` — `ApiClient` is still a mock standing in
/// for a backend that doesn't exist yet (see its own TODOs), but
/// `SharedPreferences` is real on-device storage today.
///
/// Also the one file in this feature that maps [ApiClient]'s own DTOs
/// ([FlowManifestDto]) onto flow's domain types ([ResolvedFlowManifest]) —
/// see api_dtos.dart's doc comment for why that mapping belongs here, and
/// the boundary this file crosses to do it: [ApiClient.fetchFlowManifest]
/// still names its own parameter `flowId` (see api_client.dart's doc
/// comment) even though every name in this file itself is `workflowId` —
/// see NOTES.md's Phase 5 for why that mismatch wasn't also renamed.
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
    final dto = await apiClient.fetchFlowManifest(flowId: workflowId, clientId: clientId, caseId: caseId);
    return _toResolvedFlowManifest(dto, workflowId: workflowId, clientId: clientId);
  }

  /// Pure mapping, no I/O. [FlowManifestDto] no longer carries
  /// `flowId`/`clientId`/`fetchedAt` — the confirmed backend response has
  /// no such echo fields (see NOTES.md) — so [workflowId]/[clientId] come
  /// from this call's own parameters (already known before the request was
  /// made) and `fetchedAt` is stamped here, at mapping time, the same
  /// place it always effectively happened even when it looked like it came
  /// from the DTO. [dto.caseId] now flows straight onto the domain type —
  /// see NOTES.md's Phase 1 for why this and workflowVersion (still
  /// unconsumed) were treated differently.
  ResolvedFlowManifest _toResolvedFlowManifest(
    FlowManifestDto dto, {
    required String workflowId,
    required String clientId,
  }) {
    return ResolvedFlowManifest(
      workflowId: workflowId,
      clientId: clientId,
      caseId: dto.caseId,
      fetchedAt: DateTime.now(),
      stagesJson: dto.stagesJson,
    );
  }

  @override
  Future<FlowCaseState?> loadSavedCaseState(String workflowId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(workflowId));
    if (raw == null) return null;
    return FlowCaseState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
