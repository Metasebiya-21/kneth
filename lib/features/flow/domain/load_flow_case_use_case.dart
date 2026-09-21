import 'flow_case_state.dart';
import 'flow_manifest.dart';
import 'flow_repository.dart';

/// Encapsulates the one genuine business decision in how a flow case gets
/// loaded: **is a locally-saved case still trustworthy, or has it gone
/// stale and does the agent's progress need carrying forward onto a fresh
/// fetch?** That's more than mechanical forwarding to [FlowRepository] —
/// it's a real "if this, then that instead" policy (see [resume]) — which
/// is why it lives here as a use case rather than being inlined into
/// `FlowRepositoryImpl` (which only knows how to fetch/save/load, not when
/// to prefer one over the other) or into the presentation notifier (which
/// should only need to ask "give me a ready case" and act on the answer).
///
/// [start] has no such decision to make — "fetch fresh, begin at the
/// first stage" is pure forwarding — but it's kept alongside [resume]
/// since both exist to answer the same question ("what case state should
/// the agent see right now?") and share the same dependency.
class LoadFlowCaseUseCase {
  final FlowRepository repository;

  const LoadFlowCaseUseCase(this.repository);

  /// Always a fresh network fetch, positioned at the first stage — used
  /// when starting a brand new case, or when the agent explicitly chooses
  /// to discard a saved one and start over.
  Future<FlowCaseState> start(FlowManifest manifest) async {
    final resolved = await repository.fetchManifest(
      workflowId: manifest.workflowId,
      clientId: manifest.clientId,
    );
    return FlowCaseState.initial(resolved);
  }

  /// Looks for a previously-saved, in-progress case for [manifest].
  /// Returns null if there's nothing to resume. If what's saved has gone
  /// stale (see [ResolvedFlowManifest.isStale]), re-fetches the manifest —
  /// the backend's config for this client may have changed — but keeps the
  /// agent's stage position and already-collected values rather than
  /// throwing the in-progress case away just because the manifest needed
  /// refreshing.
  ///
  /// The refresh sends [saved]'s own `caseId`, not just [manifest]'s
  /// `workflowId`/`clientId` — the confirmed backend's resume path pins
  /// itself to the case's own client (its own test:
  /// `test_fetch_flow_manifest_resume_checks_the_cases_own_client_not_the_body`),
  /// ignoring `client_id`/`workflow_id` on the body entirely whenever a
  /// `case_id` is present. `workflowId`/`clientId` are still sent alongside
  /// it (harmless on that path, and still what a real *new*-case fetch
  /// needs), but `caseId` is what actually determines which case comes
  /// back.
  Future<FlowCaseState?> resume(FlowManifest manifest) async {
    final saved = await repository.loadSavedCaseState(manifest.workflowId);
    if (saved == null) return null;
    if (!saved.manifest.isStale) return saved;

    final refreshed = await repository.fetchManifest(
      workflowId: manifest.workflowId,
      clientId: manifest.clientId,
      caseId: saved.manifest.caseId,
    );
    return saved.withRefreshedManifest(refreshed);
  }
}
