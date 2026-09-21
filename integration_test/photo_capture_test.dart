// Real-device counterpart to the narrowed
// test/features/native_capture/presentation/photo_capture_screen_test.dart
// (see that file's own doc comment, and NOTES.md's Phase 4 item 3, for the
// full account of why the equivalent flutter_test/flutter_tester version of
// this test hung reproducibly and was reverted).
//
// This is the same test content that once lived in the widget-test file —
// ImagePickerPlatform mocked via its own PlatformInterface seam, the same
// mechanism path_provider's and flutter_secure_storage's mocks already use
// successfully elsewhere in this suite — run through integration_test
// instead of flutter_test, so it executes as a real Flutter app process
// (here: in Chrome, via `flutter test integration_test/photo_capture_test.dart
// -d chrome`) rather than inside flutter_tester's headless engine. If the
// hang was specific to flutter_tester's own handling of this particular
// plugin mock (the prior investigation's process of elimination pointed
// there without confirming it), a structurally different runner is the
// right next thing to try — not the same mechanism again.
//
// Why Chrome, not macOS desktop: `flutter devices` lists both in this
// environment, but macOS desktop integration tests build through Xcode, and
// `xcode-select -p` here resolves to the Command Line Tools only (`xcodebuild
// -version` fails outright) — a full Xcode install isn't present, confirmed
// by `flutter doctor -v` flagging it directly. Chrome needs no Xcode/
// CocoaPods and was confirmed reachable. ImagePickerPlatform is mocked at
// the platform-interface level (not a real platform channel), so which
// device the test happens to run on doesn't change what's actually being
// exercised.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sdui_demo/features/flow/domain/stage_config.dart';
import 'package:sdui_demo/features/native_capture/domain/captured_media.dart';
import 'package:sdui_demo/features/native_capture/domain/media_storage_repository.dart';
import 'package:sdui_demo/features/native_capture/presentation/photo_capture_screen.dart';
import 'package:sdui_demo/services/api_client.dart';
import 'package:sdui_demo/services/api_dtos.dart';
import 'package:sdui_demo/features/flow/presentation/flow_session.dart';

/// Same fake used throughout this suite for FlowSession — see
/// test/support/fake_flow_session.dart. Duplicated locally (rather than
/// imported) because integration_test/ is a separate root package entry
/// point from test/, per the Flutter SDK's own convention, and doesn't
/// share that directory's import path.
class _FakeFlowSession implements FlowSession {
  _FakeFlowSession({required this.apiClient});

  @override
  final ApiClient apiClient;

  @override
  final Map<String, dynamic> allValues = const {};

  @override
  final String progressLabel = 'Step 01';

  @override
  final String caseId = 'fake-case-id';

  final List<Map<String, dynamic>> submittedStages = [];

  @override
  void submitStage(Map<String, dynamic> values) {
    submittedStages.add(values);
  }

  @override
  Future<void> clearSaved() async {}
}

class _FakeApiClient implements ApiClient {
  @override
  Future<FlowManifestDto> fetchFlowManifest({required String flowId, required String clientId, String? caseId}) {
    throw UnimplementedError();
  }

  @override
  Future<List<ClientSummaryDto>> fetchClients() => throw UnimplementedError();

  @override
  Future<List<WorkflowSummaryDto>> fetchWorkflows(String clientId) => throw UnimplementedError();

  @override
  Future<List<FieldOptionDto>> fetchOptions({
    required String clientId,
    required String workflowId,
    required String fieldKey,
    required Map<String, String> dependencyValues,
  }) =>
      throw UnimplementedError();

  @override
  Future<SubmitCaseResultDto> submitCase({required String? caseId, required Map<String, dynamic> values}) =>
      throw UnimplementedError();

  @override
  Future<UploadedDocumentDto> uploadDocument({required String recordId, required String kind, required String filePath}) =>
      throw UnimplementedError();
}

class _FakeMediaStorageRepository implements MediaStorageRepository {
  int persistCopyCallCount = 0;
  final List<String> deletedFilePaths = [];
  int _counter = 0;

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
    _counter++;
    return CapturedMedia(filePath: '/fake/captures/${prefix}_$_counter.jpg', type: type, capturedAt: DateTime(2026, 1, 1));
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

/// Returns a real (tiny) XFile pointing at an in-memory byte source — the
/// fake platform never touches disk, and PhotoCaptureScreen never reads
/// `photo.path` itself (only MediaStorageRepository.persistCopy would, and
/// that's faked here too), so the path just needs to be a non-null string.
class _FakeImagePickerPlatform extends ImagePickerPlatform {
  int getImageFromSourceCallCount = 0;

  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    getImageFromSourceCallCount++;
    return XFile.fromData(Uint8List.fromList([0]), name: 'camera_capture.jpg', path: '/tmp/camera_capture.jpg');
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping Take photo drives the full capture -> persist -> Confirm chain', (tester) async {
    final fakePlatform = _FakeImagePickerPlatform();
    ImagePickerPlatform.instance = fakePlatform;
    final session = _FakeFlowSession(apiClient: _FakeApiClient());
    final repository = _FakeMediaStorageRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoCaptureScreen(controller: session, stage: _photoStage, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No photo captured yet'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Take photo'));
    await tester.pumpAndSettle();

    expect(fakePlatform.getImageFromSourceCallCount, 1);
    expect(repository.persistCopyCallCount, 1);
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(session.submittedStages, [
      {'filePath': '/fake/captures/identification_card_1.jpg'},
    ]);
  });

  testWidgets('Retake deletes the previous file and captures a new one', (tester) async {
    final fakePlatform = _FakeImagePickerPlatform();
    ImagePickerPlatform.instance = fakePlatform;
    final session = _FakeFlowSession(apiClient: _FakeApiClient());
    final repository = _FakeMediaStorageRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoCaptureScreen(controller: session, stage: _photoStage, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Take photo'));
    await tester.pumpAndSettle();
    expect(repository.persistCopyCallCount, 1);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Retake'));
    await tester.pumpAndSettle();

    // The screen clears its captured state synchronously (setState) before
    // RetakePhotoUseCase's async delete resolves; wait for it explicitly
    // rather than asserting on a race.
    expect(find.text('No photo captured yet'), findsOneWidget);
    expect(repository.deletedFilePaths, ['/fake/captures/identification_card_1.jpg']);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Take photo'));
    await tester.pumpAndSettle();

    expect(repository.persistCopyCallCount, 2);
    expect(find.text('Confirm'), findsOneWidget);
  });
}
