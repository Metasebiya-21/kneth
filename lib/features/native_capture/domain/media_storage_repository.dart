import 'captured_media.dart';

/// The native-capture feature's port: what the rest of the app can ask it
/// to do ("save this captured media, give me back a reference to it"),
/// without knowing that it's actually `path_provider` + `dart:io` file
/// writes underneath. Presentation code (the capture screens) depends on
/// this abstract class, never on the concrete implementation in data/.
///
/// One shared port for both photo and signature capture, per the task
/// that started this migration — but with two methods, not one, because
/// the two capture mechanisms genuinely hand this port different raw
/// material: the camera (via image_picker) already produces a file on
/// disk that just needs copying into permanent storage, while the
/// signature canvas produces raw PNG bytes in memory with no file yet.
/// Forcing both through a single method would mean one of the two
/// callers converting its data into the other's shape for no reason.
abstract class MediaStorageRepository {
  /// Copies an already-on-disk file (e.g. what image_picker's camera
  /// capture returns, which may live in a cache directory the OS is free
  /// to clear) into permanent app storage.
  Future<CapturedMedia> persistCopy({
    required String sourcePath,
    required String prefix,
    required CaptureType type,
  });

  /// Writes raw bytes (e.g. a signature exported to PNG) into permanent
  /// app storage.
  Future<CapturedMedia> persistBytes({
    required List<int> bytes,
    required String prefix,
    required CaptureType type,
    String ext = 'png',
  });

  /// Deletes a previously-persisted file — added for [RetakePhotoUseCase]
  /// (see NOTES.md's Phase 4), closing the retake-cleanup gap this
  /// feature's own migration explicitly flagged rather than silently
  /// invented behavior for: no delete capability existed on this port at
  /// the time, so there was nothing to call. A no-op if [filePath]
  /// doesn't exist (e.g. already gone) — deleting something already
  /// absent isn't a failure worth surfacing.
  Future<void> deleteFile(String filePath);
}
