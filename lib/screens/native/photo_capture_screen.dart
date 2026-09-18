import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/flow_controller.dart';
import '../../models/stage_config.dart';
import '../../services/media_storage.dart';
import '../../widgets/stripe_identity_stepper.dart';

class PhotoCaptureScreen extends StatefulWidget {
  final FlowController controller;
  final StageConfig stage;

  const PhotoCaptureScreen({super.key, required this.controller, required this.stage});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  String? _capturedPath;
  bool _capturing = false;
  String _selectedDocType = 'National ID';

  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _laserAnimation = CurvedAnimation(parent: _laserController, curve: Curves.easeInOut);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _laserController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _capture(ImageSource source) async {
    setState(() => _capturing = true);
    try {
      final photo = await _picker.pickImage(source: source, imageQuality: 85);
      if (photo != null) {
        final persistedPath = await MediaStorage.persistCopy(photo.path, widget.stage.stageId);
        setState(() => _capturedPath = persistedPath);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _retake() => setState(() => _capturedPath = null);

  void _confirm() {
    widget.controller.submitStage({'filePath': _capturedPath, 'docType': _selectedDocType});
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
            // Document Presets
            if (_capturedPath == null) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: ['National ID', 'Business License', 'Passport', 'Kebele ID'].map((type) {
                    final isSel = _selectedDocType == type;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(type),
                        selected: isSel,
                        onSelected: (_) => setState(() => _selectedDocType = type),
                        selectedColor: const Color(0xFF0F172A),
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : const Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSel ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Guidance Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.document_scanner_rounded, color: Color(0xFF059669), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Position the card inside the green guides. Ensure lighting is uniform with zero glare.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF047857), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Viewfinder / Captured Image
            Expanded(child: Center(child: _buildViewfinder())),
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
          child: _capturedPath == null
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                        ),
                        onPressed: _capturing ? null : () => _capture(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: const Text('From Gallery', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 3,
                          shadowColor: const Color(0x33059669),
                        ),
                        onPressed: _capturing ? null : () => _capture(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_rounded, size: 20),
                        label: Text(
                          _capturing ? 'Opening Camera...' : 'Capture Document',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          foregroundColor: const Color(0xFFEF4444),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        onPressed: _retake,
                        label: const Text('Retake', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 3,
                          shadowColor: const Color(0x33059669),
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        onPressed: _confirm,
                        label: const Text('Confirm Photo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    if (_capturedPath == null) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x330F172A),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Viewfinder framing card
            Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
              child: Stack(
                children: [
                  _cornerCorner(Alignment.topLeft),
                  _cornerCorner(Alignment.topRight),
                  _cornerCorner(Alignment.bottomLeft),
                  _cornerCorner(Alignment.bottomRight),

                  // Animated Laser Scanner Line
                  AnimatedBuilder(
                    animation: _laserAnimation,
                    builder: (context, child) {
                      return Align(
                        alignment: Alignment(0, (_laserAnimation.value * 2) - 1.0),
                        child: Container(
                          height: 2.5,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Colors.transparent,
                                Color(0xFF34D399),
                                Color(0xFF10B981),
                                Color(0xFF34D399),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withAlpha(180),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Center Callout
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF34D399).withAlpha(120), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withAlpha(60),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.center_focus_strong_rounded, size: 38, color: Color(0xFF34D399)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Scan $_selectedDocType',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Align borders within frame',
                  style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF10B981), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180F172A),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.file(File(_capturedPath!), fit: BoxFit.contain),
      ),
    );
  }

  Widget _cornerCorner(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          border: Border(
            top: alignment == Alignment.topLeft || alignment == Alignment.topRight
                ? const BorderSide(color: Color(0xFF34D399), width: 4)
                : BorderSide.none,
            bottom: alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight
                ? const BorderSide(color: Color(0xFF34D399), width: 4)
                : BorderSide.none,
            left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
                ? const BorderSide(color: Color(0xFF34D399), width: 4)
                : BorderSide.none,
            right: alignment == Alignment.topRight || alignment == Alignment.bottomRight
                ? const BorderSide(color: Color(0xFF34D399), width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
