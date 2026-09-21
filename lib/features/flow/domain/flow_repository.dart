import 'flow_case_state.dart';
import 'flow_manifest.dart';

/// The flow feature's port: what the rest of the app can ask it to do
/// (fetch a manifest, save/load/clear a case's local progress) without
/// knowing that it's actually `ApiClient` (remote) plus `SharedPreferences`
/// (local) underneath. Unlike sync's `SyncRepository` or native_capture's
/// `MediaStorageRepository` — each backed by exactly one kind of data
/// source — this is the first feature where a single repository genuinely
/// composes both a remote and a local data source, because "resume a case"
/// is a genuine composition of the two: check local storage, and possibly
/// still need the remote source too if what's local has gone stale (see
/// [LoadFlowCaseUseCase]).
abstract class FlowRepository {
  /// Fetches the fully-resolved manifest for [workflowId] as configured for
  /// [clientId] — a fresh network call, every time. [caseId] is null to
  /// start a brand-new case, or a previously-returned
  /// [ResolvedFlowManifest.caseId] to resume one — see
  /// [LoadFlowCaseUseCase.resume], the only caller that ever passes one.
  Future<ResolvedFlowManifest> fetchManifest({
    required String workflowId,
    required String clientId,
    String? caseId,
  });

  /// The locally-persisted case for [workflowId], if any was saved.
  Future<FlowCaseState?> loadSavedCaseState(String workflowId);

  /// Persists [state] locally so the case survives an app restart.
  Future<void> saveCaseState(FlowCaseState state);

  /// Clears whatever's locally persisted for [workflowId], e.g. once a
  /// case has synced successfully or the agent chooses to start over.
  Future<void> clearSavedCaseState(String workflowId);
}
