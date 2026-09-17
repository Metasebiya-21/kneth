import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local, persistent storage for captured media (photos, signatures) so
/// files survive an app restart — everything here lives under the app's
/// own documents directory. Nothing is uploaded until [SyncEngine] runs.
class MediaStorage {
  static Future<Directory> _capturesDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/captures');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copies [sourcePath] into persistent app storage and returns the new
  /// path. Plugins like image_picker may hand back a path in a cache
  /// directory the OS is free to clear, so capture screens should route
  /// through this before calling `submitStage`.
  static Future<String> persistCopy(String sourcePath, String prefix) async {
    final dir = await _capturesDir();
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final destination = File('${dir.path}/$fileName');
    await File(sourcePath).copy(destination.path);
    return destination.path;
  }

  /// Writes raw bytes (e.g. an exported signature PNG) into persistent app
  /// storage and returns the new path.
  static Future<String> persistBytes(
    List<int> bytes,
    String prefix, {
    String ext = 'png',
  }) async {
    final dir = await _capturesDir();
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
