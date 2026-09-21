import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../flow/domain/stage_config.dart';
import '../../flow/presentation/flow_session.dart';
import '../data/media_storage_repository_impl.dart';
import '../domain/captured_media.dart';
import '../domain/media_storage_repository.dart';
import '../domain/retake_photo_use_case.dart';
import 'media_storage_provider.dart';

/// Native capture screen backing `nativeHandler: "photo_capture"` (identity
/// documents, and — as a placeholder, per current scope — liveness checks
/// that don't yet have a vendor SDK wired in).
///
/// Still called by `flow_screen.dart` exactly the way it always was
/// (`PhotoCaptureScreen(controller: ..., stage: ...)`) and still hands its
/// result to flow exactly the same way
/// (`controller.submitStage({'filePath': ...})`) — [controller] used to be
/// a `FlowController`, and is a [FlowSession] now that flow itself has
/// been migrated too, but the member this file calls on it didn't change,
/// so this screen's own logic didn't need to either.
class PhotoCaptureScreen extends StatelessWidget {
  final FlowSession controller;
  final StageConfig stage;

  /// Normally left null — production gets a real
  /// [MediaStorageRepositoryImpl]. Tests can pass a fake in instead; see
  /// sync_screen.dart's `repository` parameter for the same seam.
  final MediaStorageRepository? repository;

  const PhotoCaptureScreen({
    super.key,
    required this.controller,
    required this.stage,
    this.repository,
  });

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        mediaStorageRepositoryProvider.overrideWithValue(
          repository ?? const MediaStorageRepositoryImpl(),
        ),
      ],
      child: _PhotoCaptureView(controller: controller, stage: stage),
    );
  }
}

class _PhotoCaptureView extends ConsumerStatefulWidget {
  final FlowSession controller;
  final StageConfig stage;

  const _PhotoCaptureView({required this.controller, required this.stage});

  @override
  ConsumerState<_PhotoCaptureView> createState() => _PhotoCaptureViewState();
}

class _PhotoCaptureViewState extends ConsumerState<_PhotoCaptureView> {
  final ImagePicker _picker = ImagePicker();
  String? _capturedPath;
  bool _capturing = false;

  Future<void> _capture() async {
    setState(() => _capturing = true);
    try {
      final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo != null) {
        // image_picker may return a cache-directory path that the OS can
        // clear; persist into permanent app storage so it survives restarts.
        final media = await ref.read(mediaStorageRepositoryProvider).persistCopy(
              sourcePath: photo.path,
              prefix: widget.stage.stageId,
              type: CaptureType.photo,
            );
        setState(() => _capturedPath = media.filePath);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  // Deletes the previously-persisted file so a discarded photo never
  // lingers on disk — a gap explicitly flagged, not silently carried
  // forward, when this screen was first migrated (no delete capability
  // existed on MediaStorageRepository at the time). See
  // RetakePhotoUseCase's own doc comment and NOTES.md's Phase 4.
  Future<void> _retake() async {
    final previous = _capturedPath;
    setState(() => _capturedPath = null);
    await RetakePhotoUseCase(ref.read(mediaStorageRepositoryProvider)).execute(previous);
  }

  void _confirm() {
    widget.controller.submitStage({'filePath': _capturedPath});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.controller.progressLabel)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(widget.stage.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Expanded(child: Center(child: _buildPreview())),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _capturedPath == null
              ? ElevatedButton.icon(
                  onPressed: _capturing ? null : _capture,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_capturing ? 'Opening camera...' : 'Take photo'),
                )
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _retake,
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _confirm,
                        child: const Text('Confirm'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_capturedPath == null) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.document_scanner_outlined, size: 64),
          SizedBox(height: 16),
          Text('No photo captured yet'),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(File(_capturedPath!), fit: BoxFit.contain),
    );
  }
}
