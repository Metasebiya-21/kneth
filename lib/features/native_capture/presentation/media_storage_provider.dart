import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/media_storage_repository.dart';

/// Provides the [MediaStorageRepository] the capture screens should save
/// through.
///
/// Unlike sync's `syncRepositoryProvider`, this one has no per-instance
/// construction data to wait for (no `ApiClient`, no case-specific state —
/// `MediaStorageRepositoryImpl` just needs `path_provider`/`dart:io`,
/// which are the same for every capture, every time). It would be
/// reasonable to give this a real default right here. It's still built as
/// a placeholder that throws unless overridden, and each capture screen
/// still opens its own [ProviderScope] override (see [PhotoCaptureScreen],
/// [SignatureCaptureScreen]) — purely to keep the same shape sync_screen.dart
/// established, so a reader who's seen one feature migration recognizes
/// the next one immediately, and so the same test seam (an optional
/// constructor parameter tests can pass a fake into) is available here too.
final mediaStorageRepositoryProvider = Provider<MediaStorageRepository>((ref) {
  throw UnimplementedError(
    'mediaStorageRepositoryProvider has no default — it must be overridden, '
    'see PhotoCaptureScreen/SignatureCaptureScreen.',
  );
});
