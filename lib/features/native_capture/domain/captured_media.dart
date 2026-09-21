/// Which native capture mechanism produced a [CapturedMedia] — a camera
/// shot vs. a hand-drawn signature exported to an image. Recorded because
/// the two are captured through completely different mechanisms (see
/// [MediaStorageRepository]'s two methods), even though they're persisted
/// and referenced the same way once captured.
enum CaptureType { photo, signature }

/// A piece of media (a photo, a signature) once it's safely saved to
/// permanent, on-device storage. [filePath] is what actually gets handed
/// to `FlowController.submitStage` today (as `{'filePath': ...}`) — [type]
/// and [capturedAt] aren't consumed anywhere yet, but they're what a
/// "captured media" naturally is, and they were already implicit in the
/// old code (the type was implied by which screen called `MediaStorage`,
/// and a capture timestamp was already baked into the saved file's name).
/// Naming them here makes them explicit, plain-Dart domain concepts
/// instead of undocumented conventions.
class CapturedMedia {
  final String filePath;
  final CaptureType type;
  final DateTime capturedAt;

  const CapturedMedia({
    required this.filePath,
    required this.type,
    required this.capturedAt,
  });
}
