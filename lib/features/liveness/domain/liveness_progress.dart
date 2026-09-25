/// Where a case stands on the on-device liveness check, as counted by the BACKEND.
///
/// The attempt limit used to be a counter in app memory (reset by any restart, so
/// it was a UX guard only). The backend now counts attempts per case, refuses a
/// further one outright and moves an exhausted case to manual review, so this is
/// just a plain-Dart view of what the server reported. The limit itself
/// ([maxAttempts]) comes from the server; nothing here hard-codes it.
///
/// `attestedPassRecorded` is the device's own claim as recorded, never a
/// verification.
class LivenessProgress {
  final String caseStatus;
  final int attemptsUsed;

  /// Attempts whose outcome the backend has recorded (a started attempt that is still open is not).
  final int attemptsCompleted;
  final int maxAttempts;
  final int attemptsRemaining;
  final bool attestedPassRecorded;

  /// A supervisor's decision, once made: the review method and `accepted`/`rejected`.
  final String? overrideMethod;
  final String? overrideDecision;

  const LivenessProgress({
    required this.caseStatus,
    required this.attemptsUsed,
    required this.attemptsCompleted,
    required this.maxAttempts,
    required this.attemptsRemaining,
    required this.attestedPassRecorded,
    this.overrideMethod,
    this.overrideDecision,
  });

  /// Every attempt is used and the case is waiting for a supervisor.
  bool get awaitingManualReview => caseStatus == 'needs_manual_review';

  /// A supervisor accepted the case in place of the check: the stage is done.
  bool get overrideAccepted => overrideDecision == 'accepted';

  /// The case was declined (a supervisor's rejection): nothing more can be done from the app.
  bool get declined => caseStatus == 'rejected';
}
