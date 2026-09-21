import 'media_storage_repository.dart';

/// Closes a gap explicitly flagged, not silently carried forward, since
/// native_capture's own migration (see NOTES.md): retaking a photo used
/// to leave the previously-persisted file orphaned on disk forever,
/// because no delete capability existed on [MediaStorageRepository] at
/// the time, and inventing one then would have been new behavior beyond
/// that migration's own scope. It does now (NOTES.md's Phase 4) — and
/// "delete the old file before/when discarding it" is a real decision
/// (a cleanup *policy*, not mechanical forwarding — the alternative of
/// never deleting is equally mechanical), which is why it lives here as
/// a use case rather than being inlined into the capture screen, the
/// same bar [LoadFlowCaseUseCase] was held to.
class RetakePhotoUseCase {
  final MediaStorageRepository repository;

  const RetakePhotoUseCase(this.repository);

  /// Deletes [previousFilePath] if one exists — a no-op when starting
  /// fresh (nothing captured yet to clean up).
  Future<void> execute(String? previousFilePath) async {
    if (previousFilePath == null) return;
    await repository.deleteFile(previousFilePath);
  }
}
