// The same capture chain, but through the REAL ImagePicker class with only
// ImagePickerPlatform.instance faked — i.e. the default `pickPhotoWithCamera`
// path that production uses, rather than the PickPhoto seam. This is the
// mechanism whose flutter_test counterpart for the old PhotoCaptureScreen
// hung reproducibly (NOTES.md's Phase 4 item 3). Kept in its own file so an
// environment problem here can't mask the seam-based suite.
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../../support/stac_fixtures.dart';
import 'stac_test_actions.dart';
import 'stac_test_harness.dart';

class _FakeImagePickerPlatform extends ImagePickerPlatform {
  ImageSource? lastSource;
  int? lastImageQuality;

  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    lastSource = source;
    lastImageQuality = options.imageQuality;
    return XFile('/cache/from_platform.jpg');
  }
}

void main() {
  testWidgets('the default camera path calls ImagePicker with source=camera, quality 85, and persists the result',
      (tester) async {
    final platform = _FakeImagePickerPlatform();
    ImagePickerPlatform.instance = platform;
    final media = FakeMediaStorageRepository();
    final submitted = <Map<String, dynamic>>[];

    await tester.pumpWidget(stacStageApp(
      widgetJson: recordedStacWidget('identification_card'),
      submitted: submitted,
      media: media,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    expect(platform.lastSource, ImageSource.camera);
    expect(platform.lastImageQuality, 85);
    expect(media.persistedCopies, ['/cache/from_platform.jpg']);
    await tapContinue(tester);
    expect(submitted.single, {'filePath': '/fake/captures/identification_card_1.jpg'});
  });
}
