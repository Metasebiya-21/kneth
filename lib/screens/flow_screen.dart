import 'package:flutter/material.dart';
import '../controllers/flow_controller.dart';
import '../models/stage_config.dart';
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
        if (controller.isLoading) return _buildLoadingScreen();
        if (controller.loadError != null) return _buildErrorScreen(controller.loadError!);
        if (controller.isComplete) return _buildCompleteScreen(context);

        switch (controller.currentStage.screenType) {
          case ScreenType.genericForm:
            return RenderingEngineStageScreen(
              key: ValueKey('generic-${controller.currentStage.stageId}'),
              controller: controller,
              stage: controller.currentStage,
            );
          case ScreenType.nativeCapture:
            return _buildNativeCapture(context);
          case ScreenType.unknown:
            return _buildUnsupportedStage();
        }
      },
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }

  Widget _buildErrorScreen(Object error) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade600),
              const SizedBox(height: 16),
              Text('Could not load the next step.\n$error', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: controller.retry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompleteScreen(BuildContext context) {
    final values = controller.allValues;
    return Scaffold(
      appBar: AppBar(title: const Text('Flow complete')),
      body: values.isEmpty
          ? const Center(child: Text('No values collected'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: values.entries
                  .map((entry) => ListTile(
                        title: Text(entry.key),
                        trailing: Text('${entry.value}'),
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
              MaterialPageRoute(builder: (_) => SyncScreen(controller: controller)),
            ),
          ),
        ),
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
      appBar: AppBar(title: Text(controller.progressLabel)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.document_scanner_outlined, size: 64),
            const SizedBox(height: 16),
            Text('${stage.title} — native capture goes here'),
          ],
        ),
      ),
      bottomNavigationBar: _continueButton(() => controller.submitStage({})),
    );
  }

  Widget _buildUnsupportedStage() {
    return Scaffold(
      appBar: AppBar(title: Text(controller.progressLabel)),
      body: Center(
        child: Text('Unsupported stage: ${controller.currentStage.title}'),
      ),
    );
  }

  Widget _continueButton(VoidCallback onPressed) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: onPressed,
          child: const Text('Continue'),
        ),
      ),
    );
  }
}