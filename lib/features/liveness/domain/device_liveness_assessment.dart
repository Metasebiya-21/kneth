/// The app's own decision about what a finished on-device liveness session
/// means, kept apart from the screen so it can be changed (and tested)
/// without touching any UI.
///
/// **This is a device-side verdict, never a verification.** Nothing in the app
/// or the backend re-checks it; it is sent to the backend as a claim
/// ("attested_liveness_verdict") and recorded as such. Nothing in this file is
/// evidence the detection itself works: motion correlation needs a real
/// accelerometer and a real moving camera, and glare needs real light.
///
/// The decision (NOTES.md, "Device-attested liveness"):
/// - **Blocking** — any of these being true fails the check:
///   `motionCorrelationCheckFailed` (the package's own default blocker: the
///   head moved but the device didn't, i.e. a photo/screen held still),
///   `screenFlashSpoofDetected` and `depthSpoofDetected` (strong signals, and
///   only ever present if someone deliberately enables those detectors —
///   neither is enabled today).
/// - **Informational** — recorded and shown as a tip, never blocking:
///   `screenGlareDetected` and `lackOfFacialContoursDetected`. Both are sticky
///   for the whole session (one frame sets them), built on uncalibrated
///   thresholds (5–30% of pixels over 3x the average brightness; a missing
///   landmark) that sunlight, backlight or glasses can trip, so gating on them
///   would likely reject real people.
/// - **Fail closed** on anything unreadable: a missing or non-boolean blocking
///   flag, or no metadata at all, fails the check, as does the package itself
///   reporting failure.
const List<String> kBlockingAntiSpoofingFlags = [
  'motionCorrelationCheckFailed',
  'screenFlashSpoofDetected',
  'depthSpoofDetected',
];

const List<String> kInformationalAntiSpoofingFlags = [
  'screenGlareDetected',
  'lackOfFacialContoursDetected',
];

/// Reason recorded when the package itself reported failure.
const String kPackageReportedFailure = 'packageReportedFailure';

/// Reason recorded when no anti-spoofing metadata arrived at all.
const String kMissingAntiSpoofingMetadata = 'missingAntiSpoofingMetadata';

class DeviceLivenessAssessment {
  /// The device's own verdict: true only if nothing blocked.
  final bool verdict;

  /// Flags (or the two sentinel reasons above) that made [verdict] false.
  final List<String> blockingReasons;

  /// Informational flags that were set; never affect [verdict].
  final List<String> informationalFlags;

  const DeviceLivenessAssessment({
    required this.verdict,
    this.blockingReasons = const [],
    this.informationalFlags = const [],
  });

  @override
  String toString() =>
      'DeviceLivenessAssessment(verdict: $verdict, blocking: $blockingReasons, informational: $informationalFlags)';
}

DeviceLivenessAssessment assessDeviceLiveness({
  required bool packageReportedSuccess,
  required Map<String, dynamic>? antiSpoofingFlags,
}) {
  final blocking = <String>[];
  if (!packageReportedSuccess) blocking.add(kPackageReportedFailure);

  if (antiSpoofingFlags == null) {
    blocking.add(kMissingAntiSpoofingMetadata);
    return DeviceLivenessAssessment(verdict: false, blockingReasons: blocking);
  }

  for (final key in kBlockingAntiSpoofingFlags) {
    // Only an explicit `false` passes: `true`, a missing key and a
    // non-boolean all count as blocking.
    if (antiSpoofingFlags[key] != false) blocking.add(key);
  }

  final informational = [
    for (final key in kInformationalAntiSpoofingFlags)
      if (antiSpoofingFlags[key] == true) key,
  ];

  return DeviceLivenessAssessment(
    verdict: blocking.isEmpty,
    blockingReasons: blocking,
    informationalFlags: informational,
  );
}

/// Plain-language guidance for a failed attempt. The motion case is worded
/// around the known false-positive (a phone propped on a table while the
/// person turns their head), since that is the likeliest cause of a genuine
/// person failing.
String livenessFailureGuidance(DeviceLivenessAssessment assessment) {
  if (assessment.blockingReasons.contains('motionCorrelationCheckFailed')) {
    return 'Hold the phone in your hand (not on a table or stand) and turn your head slowly.';
  }
  if (assessment.blockingReasons.contains(kMissingAntiSpoofingMetadata)) {
    return 'The selfie check did not finish properly. Please try again.';
  }
  return 'We could not confirm a live person in front of the camera. Please try again.';
}

/// Tips for a check that passed but set an informational flag. Never blocks.
List<String> livenessTips(DeviceLivenessAssessment assessment) => [
      if (assessment.informationalFlags.contains('screenGlareDetected'))
        'Tip: avoid bright screens or strong light shining at the camera.',
      if (assessment.informationalFlags.contains('lackOfFacialContoursDetected'))
        'Tip: face the camera directly, with good light on your face.',
    ];
