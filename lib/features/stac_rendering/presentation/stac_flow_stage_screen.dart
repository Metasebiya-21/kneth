import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/app_exception.dart';
import '../../../widgets/app_error_view.dart';
import '../../flow/data/stac_manifest_mapper.dart' show kStacWidgetKey;
import '../../flow/domain/stage_config.dart';
import '../../native_capture/data/media_storage_repository_impl.dart';
import '../../native_capture/domain/media_storage_repository.dart';
import '../../flow/presentation/flow_notifier.dart';
import '../../flow/presentation/resolved_options_cache.dart';
import '../../liveness/presentation/liveness_launcher.dart';
import 'knet_stac_scope.dart';
import 'stac_stage_screen.dart';

/// Where captured media is persisted for Stac-rendered capture stages, and
/// how the camera is opened. Real implementations by default; tests override.
final stacMediaRepositoryProvider = Provider<MediaStorageRepository>((ref) => const MediaStorageRepositoryImpl());
final stacPickPhotoProvider = Provider<PickPhoto>((ref) => pickPhotoWithCamera);
final stacCaptureLivenessProvider = Provider<CaptureLiveness>((ref) => launchLivenessCapture);

/// Flow-facing wrapper around [StacStageScreen]: looks up this stage's Stac
/// widget in the case's Stac manifest and wires the screen to the flow's own
/// state (values so far, progress label, `submitStage`).
class StacFlowStageScreen extends ConsumerWidget {
  final StageConfig stage;

  const StacFlowStageScreen({super.key, required this.stage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(flowNotifierProvider);
    if (viewState is! FlowViewReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final caseState = viewState.caseState;
    final manifest = caseState.manifest;
    final cache = ref.read(resolvedOptionsProvider.notifier);

    // The widget tree comes from the flow's own manifest: it was fetched from the Stac route when
    // the case started (and is persisted with the case), so there is no second request.
    final stageJson = manifest.stagesJson.where((s) => s['stageId'] == stage.stageId);
    final widget = stageJson.isEmpty ? null : stageJson.first[kStacWidgetKey];
    if (widget is! Map) {
      return Scaffold(
        body: Center(
          child: AppErrorView(
            error: ClientException(422, "Stage '${stage.stageId}' has no widget definition in this case's manifest."),
          ),
        ),
      );
    }
    return StacStageScreen(
      title: stage.title,
      progressLabel: caseState.progressLabel,
      widgetJson: widget.cast<String, dynamic>(),
      initialValues: caseState.valuesForStage(stage.stageId),
      onSubmit: ref.read(flowNotifierProvider.notifier).submitStage,
      apiClient: ref.read(apiClientProvider),
      clientId: manifest.clientId,
      caseId: manifest.caseId,
      workflowId: manifest.workflowId,
      mediaRepository: ref.read(stacMediaRepositoryProvider),
      pickPhoto: ref.read(stacPickPhotoProvider),
      captureLiveness: ref.read(stacCaptureLivenessProvider),
      onOptionsResolved: (fieldKey, options) => cache.record(stage.stageId, fieldKey, options),
    );
  }
}
