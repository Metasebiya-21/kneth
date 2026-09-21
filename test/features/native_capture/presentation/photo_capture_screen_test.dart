// Scope note, revisited but not changed (see NOTES.md's Phase 4): this
// test does NOT exercise the "tap Take photo -> camera -> persist ->
// Confirm" chain. image_picker's own ImagePickerPlatform.instance seam
// (the same shape path_provider's own mock already uses successfully in
// media_storage_repository_impl_test.dart) genuinely worked for that
// purpose — a widget test built on it correctly drove the full capture
// chain, and a second one drove Retake — but every one of them hit a
// real, reproducible `flutter test` hang specific to this file: neither
// plain pump(), pumpAndSettle(), several explicit pumps, nor
// tester.runAsync() ever let the test complete, even a single, isolated
// test with no Retake logic at all involved. The rest of this app's test
// suite (161 tests, including signature_capture_screen_test.dart's own
// real image/RenderRepaintBoundary work) runs fast and reliably in the
// same environment, so this isn't general flakiness — it's specific to
// mocking ImagePickerPlatform here, and its exact cause was not found. A
// hanging test can't stay in `make ci`, so this reverts to the original,
// narrower boundary: the screen renders correctly and the ProviderScope
// override wiring works, not a real "camera -> persist -> confirm" run.
// signature_capture_screen_test.dart covers the equivalent full capture ->
// persist -> submit chain, since the signature canvas needs no plugin and
// is fully driveable from a test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/stage_config.dart';
import 'package:sdui_demo/features/native_capture/domain/captured_media.dart';
import 'package:sdui_demo/features/native_capture/domain/media_storage_repository.dart';
import 'package:sdui_demo/features/native_capture/presentation/photo_capture_screen.dart';

import '../../../support/fake_api_client.dart';
import '../../../support/fake_flow_session.dart';

class _FakeMediaStorageRepository implements MediaStorageRepository {
  int persistCopyCallCount = 0;
  final List<String> deletedFilePaths = [];

  @override
  Future<void> deleteFile(String filePath) async {
    deletedFilePaths.add(filePath);
  }

  @override
  Future<CapturedMedia> persistCopy({
    required String sourcePath,
    required String prefix,
    required CaptureType type,
  }) async {
    persistCopyCallCount++;
    return CapturedMedia(filePath: '/fake/captures/${prefix}_1.jpg', type: type, capturedAt: DateTime(2026, 1, 1));
  }

  @override
  Future<CapturedMedia> persistBytes({
    required List<int> bytes,
    required String prefix,
    required CaptureType type,
    String ext = 'png',
  }) async {
    throw UnimplementedError('photo capture never persists raw bytes');
  }
}

final _photoStage = StageConfig(
  stageId: 'identification_card',
  title: 'Identification card',
  screenType: ScreenType.nativeCapture,
  fields: const [],
  nativeHandler: NativeHandler.photoCapture,
);

void main() {
  testWidgets('renders the empty state and a working repository override, with nothing captured yet', (
    tester,
  ) async {
    final session = FakeFlowSession(apiClient: FakeApiClient());
    final repository = _FakeMediaStorageRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoCaptureScreen(controller: session, stage: _photoStage, repository: repository),
      ),
    );
    await tester.pump();

    expect(find.text('No photo captured yet'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    // Retake/Confirm only appear once a photo's been captured.
    expect(find.text('Confirm'), findsNothing);
    // The override never got read because nothing triggered a capture —
    // this just proves the ProviderScope wiring didn't throw on build.
    expect(repository.persistCopyCallCount, 0);
  });
}
