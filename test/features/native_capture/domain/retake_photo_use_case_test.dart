import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/native_capture/domain/captured_media.dart';
import 'package:sdui_demo/features/native_capture/domain/media_storage_repository.dart';
import 'package:sdui_demo/features/native_capture/domain/retake_photo_use_case.dart';

class _FakeMediaStorageRepository implements MediaStorageRepository {
  final List<String> deletedFilePaths = [];

  @override
  Future<void> deleteFile(String filePath) async {
    deletedFilePaths.add(filePath);
  }

  @override
  Future<CapturedMedia> persistCopy({required String sourcePath, required String prefix, required CaptureType type}) {
    throw UnimplementedError();
  }

  @override
  Future<CapturedMedia> persistBytes({
    required List<int> bytes,
    required String prefix,
    required CaptureType type,
    String ext = 'png',
  }) {
    throw UnimplementedError();
  }
}

void main() {
  test('deletes the previous file when one exists', () async {
    final repository = _FakeMediaStorageRepository();
    final useCase = RetakePhotoUseCase(repository);

    await useCase.execute('/fake/captures/identification_card_1.jpg');

    expect(repository.deletedFilePaths, ['/fake/captures/identification_card_1.jpg']);
  });

  test('does nothing when there is nothing to clean up yet', () async {
    final repository = _FakeMediaStorageRepository();
    final useCase = RetakePhotoUseCase(repository);

    await useCase.execute(null);

    expect(repository.deletedFilePaths, isEmpty);
  });
}
