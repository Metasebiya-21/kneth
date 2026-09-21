import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../flow/domain/stage_config.dart';
import '../../flow/presentation/flow_session.dart';
import '../data/media_storage_repository_impl.dart';
import '../domain/captured_media.dart';
import '../domain/media_storage_repository.dart';
import 'media_storage_provider.dart';

/// Native capture screen backing `nativeHandler: "signature_capture"` — a
/// simple pen-stroke canvas exported to a PNG file.
///
/// Still called by `flow_screen.dart` exactly the way it always was, and
/// still hands its result to flow the same way
/// (`controller.submitStage({'filePath': ...})`) — see
/// photo_capture_screen.dart's doc comment for why [controller] being a
/// [FlowSession] now (instead of the old, deleted `FlowController`)
/// didn't require changing anything else here.
class SignatureCaptureScreen extends StatelessWidget {
  final FlowSession controller;
  final StageConfig stage;

  /// Normally left null — see PhotoCaptureScreen's `repository` parameter
  /// for what this is for.
  final MediaStorageRepository? repository;

  const SignatureCaptureScreen({
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
      child: _SignatureCaptureView(controller: controller, stage: stage),
    );
  }
}

class _SignatureCaptureView extends ConsumerStatefulWidget {
  final FlowSession controller;
  final StageConfig stage;

  const _SignatureCaptureView({required this.controller, required this.stage});

  @override
  ConsumerState<_SignatureCaptureView> createState() => _SignatureCaptureViewState();
}

class _SignatureCaptureViewState extends ConsumerState<_SignatureCaptureView> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  bool _saving = false;

  bool get _isEmpty => _strokes.isEmpty;

  void _onPanStart(DragStartDetails details) {
    setState(() => _strokes.add([details.localPosition]));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _strokes.last.add(details.localPosition));
  }

  void _clear() => setState(() => _strokes.clear());

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final media = await ref.read(mediaStorageRepositoryProvider).persistBytes(
            bytes: bytes,
            prefix: widget.stage.stageId,
            type: CaptureType.signature,
          );
      if (!mounted) return;
      widget.controller.submitStage({'filePath': media.filePath});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
            const SizedBox(height: 8),
            const Text('Sign inside the box below', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Expanded(child: _buildCanvas()),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isEmpty ? null : _clear,
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isEmpty || _saving ? null : _confirm,
                  child: Text(_saving ? 'Saving...' : 'Confirm'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RepaintBoundary(
        key: _boundaryKey,
        child: GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          child: CustomPaint(
            painter: _SignaturePainter(_strokes),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
