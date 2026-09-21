import '../../../services/app_exception.dart';

/// Progress of a case upload. Stands in for the real app's SSE-with-
/// polling-fallback design — a UI only needs to listen to a
/// `Stream<SyncStatus>`, so the real implementation can replace
/// [SyncRepository]'s implementation later without changing any screen.
///
/// This file is plain Dart — no Flutter, no networking — which is exactly
/// what belongs in domain/: it describes a concept of the app ("a case
/// upload is either idle, in progress, succeeded, or failed"), not how
/// that upload actually happens. Importing [AppException] doesn't change
/// that: it's itself plain Dart with no infrastructure dependency of its
/// own (see its own doc comment, and this feature's boundary-script
/// allowance for it specifically).
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

  /// Value equality, not the default identity — a real gap this class
  /// never had reason to hit until NOTES.md's Phase 2: `totalSteps` used
  /// to always be the same literal (2, submit+finalize), so every
  /// `SyncUploading` in both production code and tests was a `const`
  /// expression, and Dart's const-canonicalization made two
  /// field-identical instances the *same* object — identity equality
  /// passed by coincidence. `totalSteps` is now `1 + mediaFilesByStage.
  /// length`, a runtime value SyncRepositoryImpl can't construct as a
  /// `const` — so a test's own `const SyncUploading(...)` expectation and
  /// production's dynamically-built one are different objects with the
  /// same field values, and would silently fail to compare equal without
  /// this override.
  @override
  bool operator ==(Object other) =>
      other is SyncUploading && step == other.step && totalSteps == other.totalSteps && label == other.label;

  @override
  int get hashCode => Object.hash(step, totalSteps, label);
}

class SyncSucceeded extends SyncStatus {
  const SyncSucceeded();
}

class SyncFailed extends SyncStatus {
  final AppException exception;

  const SyncFailed(this.exception);
}
