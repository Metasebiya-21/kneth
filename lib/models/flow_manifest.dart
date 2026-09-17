/// Identifies which flow to run. Stage content and sequencing are no
/// longer known client-side — [FlowController] fetches each stage from
/// [ApiClient.fetchNextStage] one at a time, server-driven.
class FlowManifest {
  final String flowId;

  FlowManifest({required this.flowId});
}