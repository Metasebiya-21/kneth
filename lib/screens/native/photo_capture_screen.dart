import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../controllers/flow_controller.dart';
import '../../models/stage_config.dart';
import '../../theme/app_colors.dart';
import '../../widgets/stripe_identity_stepper.dart';

class PhotoCaptureScreen extends StatefulWidget {
  final FlowController controller;
  final StageConfig stage;

  const PhotoCaptureScreen({
    super.key,
    required this.controller,
    required this.stage,
  });

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  XFile? _capturedImage;
  String? _errorMsg;

  late AnimationController _flashAnimController;
  late Animation<double> _flashAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _flashAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _flashAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flashAnimController, curve: Curves.easeOut),
    );

    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _flashAnimController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _errorMsg = 'No cameras found on device.');
        return;
      }

      final camera = _cameras.first;
      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _errorMsg = null;
        });
      }
    } catch (e) {
      setState(() => _errorMsg = 'Failed to initialize camera: $e');
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      // Trigger flash animation
      _flashAnimController.forward().then((_) => _flashAnimController.reverse());

      final XFile file = await _cameraController!.takePicture();
      if (mounted) {
        setState(() {
          _capturedImage = file;
          _isCapturing = false;
        });
      }
    } catch (e) {
      setState(() {
        _isCapturing = false;
        _errorMsg = 'Error capturing photo: $e';
      });
    }
  }

  void _retakePhoto() {
    setState(() => _capturedImage = null);
  }

  void _confirmAndContinue() {
    if (_capturedImage != null) {
      widget.controller.submitStage({
        '${widget.stage.stageId}.filePath': _capturedImage!.path,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: StripeIdentityStepper(
        currentStep: widget.controller.stepNumber,
        totalSteps: widget.controller.totalSteps > 0 ? widget.controller.totalSteps : 4,
        stageTitle: widget.stage.title,
        flowTitle: widget.controller.manifest.title,
        onBack: widget.controller.back,
      ),
      body: _buildBody(),
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
          child: _capturedImage != null
              ? Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _retakePhoto,
                        child: const Text('Retake'),
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
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Use Photo'),
                        onPressed: _confirmAndContinue,
                      ),
                    ),
                  ],
                )
              : ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: _isCapturing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.camera_alt_rounded, size: 20),
                  label: Text(
                    _isCapturing ? 'Processing...' : 'Capture Document',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                  ),
                  onPressed: _takePicture,
                ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.error.withAlpha(40)),
                ),
                child: const Icon(Icons.no_photography_rounded, color: AppColors.error, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'Camera Unavailable',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(_errorMsg!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (!_isCameraInitialized) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return Stack(
      children: [
        // Camera or Preview
        Positioned.fill(
          child: Container(
            color: Colors.black, // Keep the background strictly behind the camera black for contrast
            child: _capturedImage != null
                ? Image.file(File(_capturedImage!.path), fit: BoxFit.cover)
                : CameraPreview(_cameraController!),
          ),
        ),

        // Document Guide Overlay (Only show while capturing)
        if (_capturedImage == null)
          Positioned.fill(
            child: Column(
              children: [
                Expanded(flex: 1, child: Container(color: Colors.black.withAlpha(150))),
                Row(
                  children: [
                    Expanded(flex: 1, child: Container(color: Colors.black.withAlpha(150), height: 320)),
                    Container(
                      width: 300,
                      height: 320,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary, width: 3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Stack(
                        children: [
                          // Corner brackets
                          _buildCornerBracket(Alignment.topLeft),
                          _buildCornerBracket(Alignment.topRight),
                          _buildCornerBracket(Alignment.bottomLeft),
                          _buildCornerBracket(Alignment.bottomRight),
                        ],
                      ),
                    ),
                    Expanded(flex: 1, child: Container(color: Colors.black.withAlpha(150), height: 320)),
                  ],
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black.withAlpha(150),
                    alignment: Alignment.topCenter,
                    padding: const EdgeInsets.only(top: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Align document within the frame',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Flash animation
        AnimatedBuilder(
          animation: _flashAnimation,
          builder: (context, child) {
            return IgnorePointer(
              child: Container(
                color: Colors.white.withValues(alpha: _flashAnimation.value),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCornerBracket(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border(
            top: (alignment == Alignment.topLeft || alignment == Alignment.topRight)
                ? const BorderSide(color: AppColors.primary, width: 4)
                : BorderSide.none,
            bottom: (alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight)
                ? const BorderSide(color: AppColors.primary, width: 4)
                : BorderSide.none,
            left: (alignment == Alignment.topLeft || alignment == Alignment.bottomLeft)
                ? const BorderSide(color: AppColors.primary, width: 4)
                : BorderSide.none,
            right: (alignment == Alignment.topRight || alignment == Alignment.bottomRight)
                ? const BorderSide(color: AppColors.primary, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
