import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/flow_controller.dart';
import '../../models/stage_config.dart';
import '../../services/media_storage.dart';

/// Native capture screen backing `nativeHandler: "photo_capture"` (identity
/// documents, and — as a placeholder, per current scope — liveness checks
/// that don't yet have a vendor SDK wired in).
class PhotoCaptureScreen extends StatefulWidget {
  final FlowController controller;
  final StageConfig stage;

  const PhotoCaptureScreen({super.key, required this.controller, required this.stage});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _capturedPath;
  bool _capturing = false;

  Future<void> _capture() async {
    setState(() => _capturing = true);
    try {
      final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo != null) {
        // image_picker may return a cache-directory path that the OS can
        // clear; copy into persistent app storage so it survives restarts.
        final persistedPath = await MediaStorage.persistCopy(photo.path, widget.stage.stageId);
        setState(() => _capturedPath = persistedPath);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _retake() => setState(() => _capturedPath = null);

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
