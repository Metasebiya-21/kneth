/// What one finished liveness session hands back from the camera screen, in
/// plain Dart. [antiSpoofingFlags] is the package's `antiSpoofingDetection`
/// metadata map, untouched; [imagePath] is the final image the package
/// captured (null if it could not).
class LivenessCaptureResult {
  final String sessionId;
  final bool packageReportedSuccess;
  final Map<String, dynamic>? antiSpoofingFlags;
  final String? imagePath;

  const LivenessCaptureResult({
    required this.sessionId,
    required this.packageReportedSuccess,
    required this.antiSpoofingFlags,
    required this.imagePath,
  });
}

/// The detector behind the claim, recorded with it. Keep in step with the
/// exact pin in pubspec.yaml.
const String kLivenessDetector = 'smart_liveliness_detection 0.3.9';

/// The form-value key a liveness stage stores its claim under (the stage's
/// values become `<stageId>.attestedLiveness`). Named "attested" on purpose:
/// it is what the device says, not something anyone verified.
const String kAttestedLivenessKey = 'attestedLiveness';

/// The claim a liveness stage keeps in the case's values until sync sends it.
/// Plain JSON so it survives the case being saved and resumed.
Map<String, dynamic> attestedLivenessValue({
  required bool attestedLivenessVerdict,
  required Map<String, dynamic> attestedAntiSpoofingFlags,
  required String attestedSessionId,
  required int attestedAttemptsUsed,
}) =>
    {
      'attestedLivenessVerdict': attestedLivenessVerdict,
      'attestedAntiSpoofingFlags': attestedAntiSpoofingFlags,
      'attestedSessionId': attestedSessionId,
      'attestedDetector': kLivenessDetector,
      'attestedAttemptsUsed': attestedAttemptsUsed,
    };

/// The form-value key a liveness stage stores a supervisor's acceptance under when
/// the stage was completed by manual review instead of by the check. A human
/// decision, so deliberately NOT named "attested": there is nothing for sync to
/// send (the backend already holds the override).
const String kLivenessManualOverrideKey = 'livenessManualOverride';
