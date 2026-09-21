// Unlike sync's data test (which fakes ApiClient, because ApiClient itself
// is still just a mock standing in for a not-yet-built backend),
// MediaStorageRepositoryImpl's job IS real file I/O — faking dart:io here
// would only prove the fake works, not the implementation. So this test
// uses a REAL temporary directory and lets every file operation run for
// real; the only thing mocked is path_provider's platform channel, which
// is pointed at that temp directory instead of a real device path.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/native_capture/data/media_storage_repository_impl.dart';
import 'package:sdui_demo/features/native_capture/domain/captured_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_storage_test_');
    // path_provider's method channel, pointed at our temp directory instead
    // of a real platform path — see path_provider_platform_interface's
    // MethodChannelPathProvider for the channel/method names this mocks.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('persistCopy copies the source file into the app captures directory', () async {
    final source = File('${tempDir.path}/source.jpg')..writeAsStringSync('fake jpg bytes');

    const repository = MediaStorageRepositoryImpl();
    final media = await repository.persistCopy(
      sourcePath: source.path,
      prefix: 'identification_card',
      type: CaptureType.photo,
    );

    expect(media.type, CaptureType.photo);
    expect(media.filePath, contains('${tempDir.path}/captures/'));
    expect(media.filePath, endsWith('.jpg'));
    expect(await File(media.filePath).readAsString(), 'fake jpg bytes');
    // The source file itself is untouched — this is a copy, not a move.
    expect(await source.exists(), isTrue);
  });

  test('persistBytes writes raw bytes into the app captures directory', () async {
    const repository = MediaStorageRepositoryImpl();
    final bytes = [1, 2, 3, 4, 5];

    final media = await repository.persistBytes(
      bytes: bytes,
      prefix: 'consent_signature',
      type: CaptureType.signature,
    );

    expect(media.type, CaptureType.signature);
    expect(media.filePath, contains('${tempDir.path}/captures/'));
    expect(media.filePath, endsWith('.png'));
    expect(await File(media.filePath).readAsBytes(), bytes);
  });

  test('the captures directory is created once and reused, not recreated per file', () async {
    const repository = MediaStorageRepositoryImpl();

    final first = await repository.persistBytes(bytes: const [1], prefix: 'a', type: CaptureType.signature);
    final second = await repository.persistBytes(bytes: const [2], prefix: 'b', type: CaptureType.signature);

    final capturesDir = Directory('${tempDir.path}/captures');
    expect(await capturesDir.exists(), isTrue);
    expect(await File(first.filePath).exists(), isTrue);
    expect(await File(second.filePath).exists(), isTrue);
  });

  test('deleteFile removes a persisted file from disk', () async {
    const repository = MediaStorageRepositoryImpl();
    final media = await repository.persistBytes(bytes: const [1, 2, 3], prefix: 'a', type: CaptureType.signature);
    expect(await File(media.filePath).exists(), isTrue);

    await repository.deleteFile(media.filePath);

    expect(await File(media.filePath).exists(), isFalse);
  });

  test('deleteFile on a path that does not exist is a no-op, not an error', () async {
    const repository = MediaStorageRepositoryImpl();

    await repository.deleteFile('${tempDir.path}/captures/never_existed.jpg');
    // No exception thrown is the assertion — nothing else to check.
  });
}
