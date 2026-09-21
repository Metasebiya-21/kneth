import 'stage_config.dart';

/// Identifies which case to start or resume: a workflow plus the client
/// it's being run for. [FlowRepository.fetchManifest] uses both to return
/// the fully server-resolved [ResolvedFlowManifest] (global base stages
/// merged with that client's overlay) in a single upfront call.
///
/// [workflowId] — named to match what this identifier actually is per the
/// confirmed backend contract (a real `workflow_id`, obtained from
/// [ApiClient.fetchWorkflows] — see NOTES.md's Phase 3), not an
/// app-internal "flow" concept of its own. Renamed from `flowId`
/// throughout this feature's domain/data/presentation in NOTES.md's
/// Phase 5 — `lib/services/`'s own `ApiClient` interface still calls its
/// matching parameter `flowId`, deliberately not touched by that rename
/// (see api_client.dart's own doc comment on the mismatch).
class FlowManifest {
  final String workflowId;
  final String clientId;

  FlowManifest({required this.workflowId, required this.clientId});
}

/// The single-fetch, fully-resolved manifest returned by
/// [FlowRepository.fetchManifest]: every stage of the flow, in order, with
/// every field already resolved server-side. Once this is fetched, the
/// rest of the flow — advancing through stages, going back, persistence —
/// is pure local state; no further network calls happen until the whole
/// case is submitted at the end.
///
/// [stagesJson] is kept alongside the parsed [stages] purely so the raw
/// server shape round-trips through local persistence without needing a
/// full `toJson()` on every field/condition model.
///
/// [caseId] mirrors the confirmed backend's `FlowManifestResponse.case_id`
/// directly — this type is the one that shadows the wire response most
/// closely (see NOTES.md's Phase 1 for why it, not [FlowManifest] or
/// [FlowCaseState], is where a case_id belongs). It's the identifier a real
/// `submitCase` call needs, and what a later `fetchFlowManifest` call sends
/// back to resume this exact case rather than starting a new one.
class ResolvedFlowManifest {
  final String workflowId;
  final String clientId;
  final String caseId;
  final DateTime fetchedAt;
  final List<Map<String, dynamic>> stagesJson;
  final List<StageConfig> stages;

  ResolvedFlowManifest({
    required this.workflowId,
    required this.clientId,
    required this.caseId,
    required this.fetchedAt,
    required this.stagesJson,
  }) : stages = stagesJson.map(StageConfig.fromJson).toList();

  /// Whether this manifest is old enough that it should be re-fetched
  /// rather than resumed from as-is — the client/flow's configuration on
  /// the backend may have changed since it was fetched.
  bool get isStale => DateTime.now().difference(fetchedAt) > maxAge;

  static const maxAge = Duration(hours: 24);

  factory ResolvedFlowManifest.fromJson(Map<String, dynamic> json) {
    return ResolvedFlowManifest(
      workflowId: json['workflowId'] as String,
      clientId: json['clientId'] as String,
      caseId: json['caseId'] as String,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      stagesJson: (json['stages'] as List<dynamic>)
          .map((stage) => Map<String, dynamic>.from(stage as Map))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'workflowId': workflowId,
        'clientId': clientId,
        'caseId': caseId,
        'fetchedAt': fetchedAt.toIso8601String(),
        'stages': stagesJson,
      };
}
