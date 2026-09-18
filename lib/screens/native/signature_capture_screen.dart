import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

import '../../controllers/flow_controller.dart';
import '../../models/stage_config.dart';
import '../../theme/app_colors.dart';
import '../../widgets/stripe_identity_stepper.dart';

class SignatureCaptureScreen extends StatefulWidget {
  final FlowController controller;
  final StageConfig stage;

  const SignatureCaptureScreen({
    super.key,
    required this.controller,
    required this.stage,
  });

  @override
  State<SignatureCaptureScreen> createState() => _SignatureCaptureScreenState();
}

class _SignatureCaptureScreenState extends State<SignatureCaptureScreen> {
  late SignatureController _signatureController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _signatureController = SignatureController(
      penStrokeWidth: 4,
      penColor: AppColors.textPrimary,
      exportBackgroundColor: Colors.transparent,
      exportPenColor: Colors.black,
      onDrawEnd: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _saveSignature() async {
    if (_signatureController.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final ui.Image? image = await _signatureController.toImage();
      if (image == null) throw Exception("Failed to generate signature image");

      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception("Failed to format image data");

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/signature_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data.buffer.asUint8List());

      widget.controller.submitStage({
        '${widget.stage.stageId}.filePath': file.path,
        '${widget.stage.stageId}.timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving signature: $e', style: const TextStyle(color: Colors.white))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSignature = _signatureController.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: StripeIdentityStepper(
        currentStep: widget.controller.stepNumber,
        totalSteps: widget.controller.totalSteps > 0 ? widget.controller.totalSteps : 4,
        stageTitle: widget.stage.title,
        flowTitle: widget.controller.manifest.title,
        onBack: widget.controller.back,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withAlpha(40)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Please provide your legal signature within the bounds below. This will be cryptographically sealed.',
                      style: TextStyle(color: AppColors.primaryDark, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border, width: 2),
                  boxShadow: const [
                    BoxShadow(color: AppColors.shadowLight, blurRadius: 16, offset: Offset(0, 4)),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Guide lines
                    Positioned.fill(
                      child: CustomPaint(painter: _SignatureGuidePainter()),
                    ),
                    // Canvas
                    Positioned.fill(
                      child: Signature(
                        controller: _signatureController,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                    if (!hasSignature)
                      const Center(
                        child: Text(
                          'Sign Here',
                          style: TextStyle(
                            color: AppColors.border,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
            boxShadow: [
              BoxShadow(color: AppColors.shadowLight, blurRadius: 16, offset: Offset(0, -4)),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: const Text('Clear'),
                  onPressed: hasSignature
                      ? () {
                          _signatureController.clear();
                          setState(() {});
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: _isProcessing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    _isProcessing ? 'Processing...' : 'Accept Signature',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                  ),
                  onPressed: hasSignature && !_isProcessing ? _saveSignature : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignatureGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final double startY = size.height * 0.75;
    
    // Draw the baseline
    canvas.drawLine(
      Offset(size.width * 0.1, startY),
      Offset(size.width * 0.9, startY),
      paint,
    );

    // Draw the X marker
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'X',
        style: TextStyle(color: AppColors.textMuted, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width * 0.1, startY - 24));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
