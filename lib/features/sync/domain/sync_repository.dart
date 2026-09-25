import 'sync_status.dart';

/// The sync feature's "port": what the rest of the app can ask sync to do,
/// without knowing how it's actually done (which HTTP client, which
/// endpoints, in how many requests). Presentation code depends on this
/// abstract class, never on the concrete implementation in data/ — that's
/// what makes it possible to swap the real network implementation for a
/// fake one in tests without changing any widget.
///
/// One method — callers only ever care about "submit this case and tell
/// me how it's going," even though the implementation now makes a
/// variable number of API calls internally (one `submitCase`, then one
/// `uploadDocument` (individual) or `uploadBusinessDocument` (business)
/// per captured file, chosen by the file's `DocumentKind` — see NOTES.md's Phase 2 for why
/// the old two-step submit+finalize shape became this instead).
abstract class SyncRepository {
  /// Submits the entire collected case's field [values], then uploads
  /// each entry of [mediaFilesByStage] (stage id → captured file path)
  /// against the record `submitCase` creates — reporting progress as a
  /// stream of [SyncStatus], ending in [SyncSucceeded] or [SyncFailed].
  ///
  /// [mediaFilesByStage] is keyed by stage id, not a flat list — a real
  /// drift found while wiring this up (see NOTES.md's Phase 2): uploading
  /// a captured file needs to know which native-capture stage produced it
  /// (to map onto the confirmed backend's `DocumentKind`), which a flat
  /// `List<String>` of paths had already discarded by the time it reached
  /// this method.
  ///
  /// [attestedLivenessByStage] (stage id → the stage's `attestedLiveness`
  /// value) are the device's own liveness claims; each is recorded against the
  /// individual record `submitCase` creates, as an *attested* result (the
  /// backend checks nothing). Resolved up front and failed loudly like a
  /// document, since it can only be sent once `submitCase` has returned a
  /// `recordId`.
  ///
  /// [caseId] comes from `FlowSession.caseId` (the case's server-assigned
  /// id, captured at manifest-fetch time — see NOTES.md's Phase 1) and is
  /// required to be explicitly passed, the same reasoning as
  /// `ApiClient.submitCase`'s own [caseId] parameter.
  Stream<SyncStatus> submitCase({
    required String? caseId,
    required Map<String, dynamic> values,
    required Map<String, String> mediaFilesByStage,
    Map<String, Map<String, dynamic>> attestedLivenessByStage = const {},
  });
}
