import 'package:flutter/material.dart';

import '../controllers/flow_controller.dart';
import '../models/stage_config.dart';
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
            final inOffset = isForward ? const Offset(0.25, 0.0) : const Offset(-0.25, 0.0);
            return SlideTransition(
              position: Tween<Offset>(begin: inOffset, end: Offset.zero).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.97, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                  ),
                  child: child,
                ),
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
      backgroundColor: Color(0xFFF8FAFC),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF059669), strokeWidth: 3),
            SizedBox(height: 18),
            Text(
              'Initializing Server-Driven Flow...',
              style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageLoadingScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(controller.manifest.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF059669), strokeWidth: 3),
            const SizedBox(height: 18),
            Text(
              'Loading next stage schema...',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(Object error) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Workflow Interrupted')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFDC2626)),
              ),
              const SizedBox(height: 20),
              const Text(
                'Could Not Load Step',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
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
      backgroundColor: const Color(0xFFF8FAFC),
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Text(controller.progressLabel)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.document_scanner_outlined, size: 64, color: Color(0xFF059669)),
            const SizedBox(height: 16),
            Text(
              '${stage.title} — Native Capture',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Text(controller.progressLabel)),
      body: Center(
        child: Text('Unsupported stage: ${controller.currentStage.title}'),
      ),
    );
  }
}