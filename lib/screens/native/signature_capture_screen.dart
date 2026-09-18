import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../controllers/flow_controller.dart';
import '../../models/stage_config.dart';
import '../../services/media_storage.dart';
import '../../widgets/stripe_identity_stepper.dart';

class SignatureCaptureScreen extends StatefulWidget {
  final FlowController controller;
  final StageConfig stage;

  const SignatureCaptureScreen({super.key, required this.controller, required this.stage});

  @override
  State<SignatureCaptureScreen> createState() => _SignatureCaptureScreenState();
}

class _SignatureCaptureScreenState extends State<SignatureCaptureScreen> {
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

  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
    }
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final path = await MediaStorage.persistBytes(bytes, widget.stage.stageId);
      if (!mounted) return;
      widget.controller.submitStage({'filePath': path});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: StripeIdentityStepper(
        currentStep: widget.controller.stepNumber,
        totalSteps: widget.controller.totalSteps > 0 ? widget.controller.totalSteps : 4,
        stageTitle: widget.stage.title,
        flowTitle: widget.controller.manifest.title,
        onBack: () {
          widget.controller.back();
          if (Navigator.of(context).canPop() && widget.controller.progressLabel == 'Step 01') {
            Navigator.of(context).pop();
          }
        },
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Regulatory Consent Notice
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_rounded, color: Color(0xFF059669), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'By providing your signature, you certify the accuracy of all registered information and consent to National ID verification.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF047857), fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Toolbar
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Legal Signatory Surface',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF0F172A)),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: _isEmpty ? null : _undo,
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: const Text('Undo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: const Color(0xFFEF4444),
                      ),
                      onPressed: _isEmpty ? null : _clear,
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      label: const Text('Clear', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Interactive Pad
            Expanded(child: _buildCanvas()),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 3,
              shadowColor: const Color(0x33059669),
            ),
            onPressed: _isEmpty || _saving ? null : _confirm,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_rounded, size: 20),
            label: Text(
              _saving ? 'Securing Signature...' : 'Confirm Legal Signature',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background Watermark Shield
          const Positioned(
            right: 20,
            bottom: 20,
            child: Opacity(
              opacity: 0.04,
              child: Icon(
                Icons.draw_rounded,
                size: 160,
                color: Color(0xFF0F172A),
              ),
            ),
          ),

          // Signatory Baseline Guideline
          Positioned(
            bottom: 45,
            left: 24,
            right: 24,
            child: Container(
              height: 1.5,
              color: const Color(0xFFCBD5E1),
            ),
          ),
          const Positioned(
            bottom: 16,
            left: 24,
            right: 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.edit_outlined, size: 14, color: Color(0xFF94A3B8)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sign with finger above guideline (ዲጂታል ፊርማ)',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          RepaintBoundary(
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
        ],
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
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
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
