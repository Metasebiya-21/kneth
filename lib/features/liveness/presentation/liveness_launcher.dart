import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../services/app_exception.dart';
import '../domain/liveness_capture_result.dart';
import 'liveness_capture_screen.dart';

/// Opens the selfie check and returns what it produced, or null if the agent
/// backed out. The default is the real camera flow; tests pass their own, which
/// is the platform boundary: a fake launcher proves the app's own handling of a
/// result, never that the detection works.
typedef CaptureLiveness = Future<LivenessCaptureResult?> Function(BuildContext context);

Future<LivenessCaptureResult?> launchLivenessCapture(BuildContext context) async {
  final List<CameraDescription> cameras;
  try {
    cameras = await availableCameras();
  } on CameraException {
    throw const ForbiddenException('The camera is not available. Check that camera access is allowed for this app in Settings.');
  }
  if (cameras.isEmpty) {
    throw const ForbiddenException('This device has no camera, so the selfie check cannot be done here.');
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<LivenessCaptureResult>(
    MaterialPageRoute(builder: (_) => LivenessCaptureScreen(cameras: cameras), fullscreenDialog: true),
  );
}
