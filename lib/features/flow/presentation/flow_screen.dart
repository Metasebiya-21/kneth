import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/app_exception.dart';
import '../../../widgets/app_error_view.dart';
import '../../stac_rendering/presentation/stac_flow_stage_screen.dart';
import '../../sync/presentation/sync_screen.dart';
import '../domain/flow_case_state.dart';
import '../domain/flow_manifest.dart';
import '../domain/stage_config.dart';
import 'flow_notifier.dart';
import 'flow_session.dart';
import 'summary_value.dart';

/// The flow feature's entry screen: kicks off [FlowNotifier.start] or
/// [FlowNotifier.resume] once mounted (deferred via a post-frame callback
/// — see NOTES.md on why a provider-mutating call can't happen directly in
/// `initState`), then renders whatever [FlowViewState] comes back.
class FlowScreen extends ConsumerStatefulWidget {
  final FlowManifest manifest;

  /// True when this screen should resume a previously-saved case (see
  /// [FlowNotifier.resume]) rather than starting a brand new one.
  final bool resumeMode;

  const FlowScreen({super.key, required this.manifest, this.resumeMode = false});

  @override
  ConsumerState<FlowScreen> createState() => _FlowScreenState();
}

class _FlowScreenState extends ConsumerState<FlowScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final notifier = ref.read(flowNotifierProvider.notifier);
    if (widget.resumeMode) {
      notifier.resume(widget.manifest);
    } else {
      notifier.start(widget.manifest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flowNotifierProvider);
    final session = RiverpodFlowSession(ref);

    return switch (state) {
      FlowViewLoading() => _buildLoadingScreen(),
      FlowViewError(:final error) => _buildErrorScreen(error),
      FlowViewReady(:final caseState) when caseState.isComplete =>
        _buildCompleteScreen(context, session, caseState),
      FlowViewReady(:final caseState) => _buildStage(context, session, caseState),
    };
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }

  Widget _buildErrorScreen(AppException error) {
    // Now the same shared widget SyncStatus.failed and
    // DynamicFieldOptionsStatus.failed already render through (see
    // NOTES.md's Phase 4) — FlowViewError used to carry a bare Object and
    // build its own ad hoc message/retry button here.
    return Scaffold(
      body: Center(
        child: AppErrorView(
          error: error,
          onRetry: () => ref.read(flowNotifierProvider.notifier).retry(),
        ),
      ),
    );
  }

  Widget _buildCompleteScreen(BuildContext context, FlowSession session, FlowCaseState caseState) {
    final values = caseState.allValues;
    return Scaffold(
      appBar: AppBar(title: const Text('Flow complete')),
      body: values.isEmpty
          ? const Center(child: Text('No values collected'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: values.entries
                  // A key/value row that wraps, not a ListTile with the value as
                  // `trailing`: an unbounded trailing Text throws a layout
                  // exception for any long value (e.g. a free-text note), which
                  // used to crash this whole screen.
                  .map((entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 2, child: Text(entry.key)),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 3,
                              child: SummaryValueText(caseState: caseState, payloadKey: entry.key, value: entry.value),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Sync now'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SyncScreen(controller: session)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context, FlowSession session, FlowCaseState caseState) {
    final stage = caseState.currentStage;
    // Every recognized stage (forms and native capture alike) is rendered from
    // the Stac manifest; only a screen type this app version doesn't know falls
    // back to the plain "unsupported" screen.
    if (stage.screenType == ScreenType.unknown) return _buildUnsupportedStage(session, stage);
    return StacFlowStageScreen(key: ValueKey('stac-${stage.stageId}'), stage: stage);
  }

  Widget _buildUnsupportedStage(FlowSession session, StageConfig stage) {
    return Scaffold(
      appBar: AppBar(title: Text(session.progressLabel)),
      body: Center(
        child: Text('Unsupported stage: ${stage.title}'),
      ),
    );
  }
}
