import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/captured_media.dart';
import '../domain/media_storage_repository.dart';

/// The real implementation of [MediaStorageRepository] — this is almost
/// exactly the old `MediaStorage` class's body, moved here and turned from
/// static methods into instance methods so it can implement an interface.
///
/// Unlike sync's `ApiClient` (still fully mocked, no real network calls
/// yet), `path_provider` and `dart:io` here are genuinely real —
/// `getApplicationDocumentsDirectory()` talks to the actual platform, and
/// `File.copy`/`writeAsBytes` do real disk I/O. This is the first data/
/// implementation in this codebase's feature-first migration that isn't
/// standing in for a not-yet-built backend.
class MediaStorageRepositoryImpl implements MediaStorageRepository {
  const MediaStorageRepositoryImpl();

  Future<Directory> _capturesDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/captures');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<CapturedMedia> persistCopy({
    required String sourcePath,
    required String prefix,
    required CaptureType type,
  }) async {
    final dir = await _capturesDir();
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final destination = File('${dir.path}/$fileName');
    await File(sourcePath).copy(destination.path);
    return CapturedMedia(filePath: destination.path, type: type, capturedAt: DateTime.now());
  }

  @override
  Future<CapturedMedia> persistBytes({
    required List<int> bytes,
    required String prefix,
    required CaptureType type,
    String ext = 'png',
  }) async {
    final dir = await _capturesDir();
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return CapturedMedia(filePath: file.path, type: type, capturedAt: DateTime.now());
  }

  @override
  Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
