import 'package:flutter/material.dart';

import '../controllers/flow_controller.dart';
import '../models/stage_config.dart';
import '../theme/app_colors.dart';
import '../widgets/revolut_receipt_sheet.dart';
import 'native/photo_capture_screen.dart';
import 'native/signature_capture_screen.dart';
import 'rendering_engine_stage_screen.dart';
import 'sync_screen.dart';

class FlowScreen extends StatelessWidget {
  final FlowController controller;

  const FlowScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isLoading && controller.stepNumber == 0) return _buildLoadingScreen();
        if (controller.loadError != null && controller.stepNumber == 0) return _buildErrorScreen(controller.loadError!);
        if (controller.isComplete) return _buildCompleteScreen(context);

        Widget currentStageWidget;
        String stageKey;

        if (controller.isLoading) {
          currentStageWidget = _buildStageLoadingScreen();
          stageKey = 'stage-loading';
        } else if (controller.loadError != null) {
          currentStageWidget = _buildErrorScreen(controller.loadError!);
          stageKey = 'stage-error';
        } else {
          stageKey = 'stage-${controller.currentStage.stageId}';
          switch (controller.currentStage.screenType) {
            case ScreenType.genericForm:
              currentStageWidget = RenderingEngineStageScreen(
                key: ValueKey('generic-${controller.currentStage.stageId}'),
                controller: controller,
                stage: controller.currentStage,
              );
              break;
            case ScreenType.nativeCapture:
              currentStageWidget = _buildNativeCapture(context);
              break;
            case ScreenType.unknown:
              currentStageWidget = _buildUnsupportedStage();
              break;
          }
        }

        final isForward = controller.direction == NavigationDirection.forward;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          transitionBuilder: (child, animation) {
            final isIncoming = child.key == ValueKey(stageKey);
            
            double scaleBegin;
            if (isForward) {
              scaleBegin = isIncoming ? 0.92 : 1.08;
            } else {
              scaleBegin = isIncoming ? 1.08 : 0.92;
            }

            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: isIncoming 
                  ? const Interval(0.2, 1.0, curve: Curves.easeOut) 
                  : const Interval(0.0, 0.8, curve: Curves.easeOut),
              ),
              child: ScaleTransition(
                scale: Tween<double>(begin: scaleBegin, end: 1.0).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                ),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(stageKey),
            child: currentStageWidget,
          ),
        );
      },
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            SizedBox(height: 18),
            Text(
              'Initializing Workflow...',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageLoadingScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(controller.manifest.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            SizedBox(height: 18),
            Text(
              'Loading next stage schema...',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(Object error) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Workflow Interrupted')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.error.withAlpha(40)),
                ),
                child: const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.error),
              ),
              const SizedBox(height: 20),
              const Text(
                'Could Not Load Step',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: controller.retry,
                label: const Text('Retry Step'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompleteScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Verification Summary', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: RevolutReceiptSheet(
        flowTitle: controller.manifest.title,
        category: controller.manifest.category,
        collectedData: controller.allValues,
        onConfirmAndSync: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => SyncScreen(controller: controller)),
          );
        },
        onEditStage: () {
          controller.back();
        },
      ),
    );
  }

  Widget _buildNativeCapture(BuildContext context) {
    final stage = controller.currentStage;
    switch (stage.nativeHandler) {
      case NativeHandler.photoCapture:
        return PhotoCaptureScreen(controller: controller, stage: stage);
      case NativeHandler.signatureCapture:
        return SignatureCaptureScreen(controller: controller, stage: stage);
      case NativeHandler.unknown:
        return _buildNativeCapturePlaceholder(stage);
    }
  }

  Widget _buildNativeCapturePlaceholder(StageConfig stage) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(controller.progressLabel)),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.document_scanner_outlined, size: 64, color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Stage — Native Capture',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: () => controller.submitStage({}),
            child: const Text('Continue'),
          ),
        ),
      ),
    );
  }

  Widget _buildUnsupportedStage() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(controller.progressLabel)),
      body: Center(
        child: Text('Unsupported stage: ${controller.currentStage.title}', style: const TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}