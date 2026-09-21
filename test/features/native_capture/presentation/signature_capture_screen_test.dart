import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/domain/stage_config.dart';
import 'package:sdui_demo/features/native_capture/domain/captured_media.dart';
import 'package:sdui_demo/features/native_capture/domain/media_storage_repository.dart';
import 'package:sdui_demo/features/native_capture/presentation/signature_capture_screen.dart';

import '../../../support/fake_api_client.dart';
import '../../../support/fake_flow_session.dart';

/// A fake at the domain boundary — no path_provider, no real file I/O —
/// same shape as sync_screen_test.dart's `_FakeSyncRepository`.
class _FakeMediaStorageRepository implements MediaStorageRepository {
  int persistBytesCallCount = 0;
  List<int>? lastBytes;
  String? lastPrefix;
  CaptureType? lastType;

  @override
  Future<void> deleteFile(String filePath) async {}

  @override
  Future<CapturedMedia> persistBytes({
    required List<int> bytes,
    required String prefix,
    required CaptureType type,
    String ext = 'png',
  }) async {
    persistBytesCallCount++;
    lastBytes = bytes;
    lastPrefix = prefix;
    lastType = type;
    return CapturedMedia(
      filePath: '/fake/captures/${prefix}_1.$ext',
      type: type,
      capturedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<CapturedMedia> persistCopy({
    required String sourcePath,
    required String prefix,
    required CaptureType type,
  }) async {
    throw UnimplementedError('signature capture never copies a file');
  }
}

final _signatureStage = StageConfig(
  stageId: 'consent_signature',
  title: 'Consent signature',
  screenType: ScreenType.nativeCapture,
  fields: const [],
  nativeHandler: NativeHandler.signatureCapture,
);

/// Finds the signature canvas's GestureDetector specifically — Material
/// buttons on this screen use their own internal gesture handling, not a
/// raw GestureDetector with onPanStart set, so this predicate is
/// unambiguous.
Finder get _canvas => find.byWidgetPredicate((w) => w is GestureDetector && w.onPanStart != null);

void main() {
  testWidgets('drawing then confirming saves through the injected repository and submits the path', (
    tester,
  ) async {
    final session = FakeFlowSession(apiClient: FakeApiClient());
    final repository = _FakeMediaStorageRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: SignatureCaptureScreen(
          controller: session,
          stage: _signatureStage,
          repository: repository,
        ),
      ),
    );
    await tester.pump();

    // Confirm starts disabled until something is drawn.
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm')).onPressed, isNull);

    await tester.drag(_canvas, const Offset(60, 0));
    await tester.pump();

    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm')).onPressed, isNotNull);

    // image.toByteData(format: png) does real PNG encoding on a background
    // thread — its completion isn't tied to the frame scheduler, so
    // pump()/pumpAndSettle() alone never observe it finishing (confirmed by
    // hand: toImage() completed fine under plain pump(), toByteData() never
    // did, even wrapping just the tap in runAsync — _confirm()'s
    // continuation after that await isn't guaranteed to still be inside
    // runAsync's real zone by the time it resumes). Polling the fake
    // repository's own call count with real delays, all inside runAsync,
    // sidesteps that entirely: it only stops once persistBytes has actually
    // been called, however many real frames that takes.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      var attempts = 0;
      while (repository.persistBytesCallCount == 0 && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 20));
        attempts++;
      }
    });
    await tester.pump();

    expect(repository.persistBytesCallCount, 1);
    expect(repository.lastPrefix, 'consent_signature');
    expect(repository.lastType, CaptureType.signature);
    // The flow session's submitStage was actually called with the fake
    // repository's returned filePath, proving the confirm flow really
    // went end to end, not just that the button was tappable.
    expect(session.submittedStages, [
      {'filePath': '/fake/captures/consent_signature_1.png'},
    ]);
  });

  testWidgets('clear empties the canvas and disables confirm again', (tester) async {
    final session = FakeFlowSession(apiClient: FakeApiClient());
    final repository = _FakeMediaStorageRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: SignatureCaptureScreen(
          controller: session,
          stage: _signatureStage,
          repository: repository,
        ),
      ),
    );
    await tester.pump();

    await tester.drag(_canvas, const Offset(60, 0));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Clear')).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear'));
    await tester.pump();

    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm')).onPressed, isNull);
    expect(repository.persistBytesCallCount, 0);
  });
}
