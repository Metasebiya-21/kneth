/// Progress of a case upload. Stands in for the real app's SSE-with-
/// polling-fallback design — a UI only needs to listen to a
/// `Stream<SyncStatus>`, so the real implementation can replace
/// [SyncEngine] later without changing any screen.
sealed class SyncStatus {
  const SyncStatus();
}

class SyncIdle extends SyncStatus {
  const SyncIdle();
}

class SyncUploading extends SyncStatus {
  final int step;
  final int totalSteps;
  final String label;

  const SyncUploading({required this.step, required this.totalSteps, required this.label});
}

class SyncSucceeded extends SyncStatus {
  const SyncSucceeded();
}

class SyncFailed extends SyncStatus {
  final String message;

  const SyncFailed(this.message);
}
