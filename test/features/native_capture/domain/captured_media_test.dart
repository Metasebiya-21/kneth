// A pure-Dart unit test, same as sync's domain tests — CapturedMedia and
// CaptureType have no Flutter or dart:io dependency, so no widget harness
// is needed to exercise them.
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/native_capture/domain/captured_media.dart';

void main() {
  test('CapturedMedia carries its file path, type, and capture time', () {
    final capturedAt = DateTime(2026, 1, 1, 12);
    final media = CapturedMedia(
      filePath: '/tmp/captures/photo_1.jpg',
      type: CaptureType.photo,
      capturedAt: capturedAt,
    );

    expect(media.filePath, '/tmp/captures/photo_1.jpg');
    expect(media.type, CaptureType.photo);
    expect(media.capturedAt, capturedAt);
  });

  test('every CaptureType is distinguishable with a switch', () {
    // Mirrors sync_status_test.dart's exhaustiveness check: a switch over
    // CaptureType with every case covered needs no `default`, which is
    // what lets a repository implementation trust it's handled every kind
    // of capture.
    String describe(CaptureType type) => switch (type) {
          CaptureType.photo => 'photo',
          CaptureType.signature => 'signature',
        };

    expect(describe(CaptureType.photo), 'photo');
    expect(describe(CaptureType.signature), 'signature');
  });
}
