import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:smart_liveliness_detection/smart_liveliness_detection.dart';

import '../domain/liveness_capture_result.dart';

/// The package's defaults for challenges and for the blocking motion check are
/// kept. Screen flash and depth detection stay off (null), so those two flags
/// are always false today.
///
/// The package's own status texts say "verification" ("Liveness verification
/// complete!"). Nothing here verifies anything (the device makes a claim, the
/// backend records it as attested), so every such string is replaced.
const LivenessConfig kLivenessConfig = LivenessConfig(
  messages: LivenessMessages(
    errorInitializingCamera:
        'The camera could not start. Check that camera access is allowed for this app in Settings, then go back and try again.',
    processingVerification: 'Finishing the selfie check…',
    verificationComplete: 'Selfie check finished',
    spoofingDetected: 'The selfie check did not pass.',
    screenFlashSpoofingDetected: 'The selfie check did not pass. Please try again.',
  ),
);

/// Wraps smart_liveliness_detection's [LivenessDetectionScreen], which owns
/// its own camera view, challenge UI and anti-spoofing logic (unlike photo
/// capture's simple take-then-confirm flow, none of that transfers). This
/// screen adds only what the app needs around it: no built-in retry overlay,
/// a back button, and popping the finished session as a
/// [LivenessCaptureResult] for the stage to judge with `assessDeviceLiveness`.
///
/// Pops `null` if the agent backs out. Nothing here decides pass or fail.
///
/// NOT verifiable without a real device: the camera stream, ML Kit face
/// detection, the accelerometer behind motion correlation, and glare/contour
/// detection. The package swallows camera initialisation failures (a denied
/// permission only changes its status text; there is no error callback), so
/// the message below and the back button are the agent's way out.
class LivenessCaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const LivenessCaptureScreen({super.key, required this.cameras});

  @override
  State<LivenessCaptureScreen> createState() => _LivenessCaptureScreenState();
}

class _LivenessCaptureScreenState extends State<LivenessCaptureScreen> {
  XFile? _finalImage;
  bool _finished = false;

  void _onFinalImage(String sessionId, XFile image, Map<String, dynamic> metadata) {
    _finalImage = image;
  }

  void _onCompleted(String sessionId, bool isSuccessful, Map<String, dynamic> metadata) {
    if (_finished) return;
    _finished = true;
    final flags = metadata['antiSpoofingDetection'];
    final result = LivenessCaptureResult(
      sessionId: sessionId,
      packageReportedSuccess: isSuccessful,
      antiSpoofingFlags: flags is Map ? Map<String, dynamic>.from(flags) : null,
      imagePath: _finalImage?.path,
    );
    // The package captures the final image before it reports completion; a
    // short pause lets the agent see the outcome before the screen closes.
    Timer(const Duration(milliseconds: 800), () {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LivenessDetectionScreen(
      cameras: widget.cameras,
      config: kLivenessConfig,
      captureFinalImage: true,
      onFinalImageCaptured: _onFinalImage,
      onLivenessCompleted: _onCompleted,
      customAppBar: AppBar(
        title: const Text('Selfie check'),
        leading: const BackButton(),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // The package's own overlay offers a "try again" that would bypass the
      // app's attempt limit; this one only says the check is finishing.
      customSuccessOverlay: const ColoredBox(
        color: Color(0xCC000000),
        child: Center(child: Text('Finishing the selfie check…', style: TextStyle(color: Colors.white, fontSize: 18))),
      ),
    );
  }
}
