// kneth_photo_capture against the real recorded identification_card stage.
// The camera is faked at the PickPhoto seam (not at ImagePickerPlatform —
// see STAC_MIGRATION_SCOPING.md section 12 for why), which also lets the
// tests raise the exact PlatformException codes image_picker's Android/iOS
// implementations raise for a denied camera permission.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/stac_fixtures.dart';
import 'stac_test_actions.dart';
import 'stac_test_harness.dart';

void main() {
  late FakeMediaStorageRepository media;
  late List<Map<String, dynamic>> submitted;
  var picks = 0;

  setUp(() {
    media = FakeMediaStorageRepository();
    submitted = [];
    picks = 0;
  });

  Future<String?> camera() async => '/cache/picked_${++picks}.jpg';

  testWidgets('the real recorded identification_card stage renders the empty state', (tester) async {
    await tester.pumpWidget(stacStageApp(
      widgetJson: recordedStacWidget('identification_card'),
      submitted: submitted,
      media: media,
      pickPhoto: camera,
    ));
    await tester.pumpAndSettle();

    expect(find.text('No photo captured yet'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Retake'), findsNothing);
  });

  testWidgets('capture persists through MediaStorageRepository under the stage prefix and submits {filePath: ...}',
      (tester) async {
    await tester.pumpWidget(stacStageApp(
      widgetJson: recordedStacWidget('identification_card'),
      submitted: submitted,
      media: media,
      pickPhoto: camera,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    expect(media.persistedCopies, ['/cache/picked_1.jpg']);
    expect(find.text('Retake'), findsOneWidget);

    await tapContinue(tester);

    // The key is `filePath`, not the widget id: SyncScreen finds captured
    // files by the 'stageId.filePath' suffix.
    expect(submitted.single, {'filePath': '/fake/captures/identification_card_1.jpg'});
  });

  testWidgets('Continue with nothing captured is blocked', (tester) async {
    await tester.pumpWidget(stacStageApp(
      widgetJson: recordedStacWidget('identification_card'),
      submitted: submitted,
      media: media,
      pickPhoto: camera,
    ));
    await tester.pumpAndSettle();

    await tapContinue(tester);

    expect(find.text('Take a photo to continue'), findsOneWidget);
    expect(submitted, isEmpty);
  });

  testWidgets('Retake deletes the previous file through the real RetakePhotoUseCase, then captures a new one',
      (tester) async {
    await tester.pumpWidget(stacStageApp(
      widgetJson: recordedStacWidget('identification_card'),
      submitted: submitted,
      media: media,
      pickPhoto: camera,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retake'));
    await tester.pumpAndSettle();

    expect(media.deleted, ['/fake/captures/identification_card_1.jpg']);
    expect(find.text('No photo captured yet'), findsOneWidget);

    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await tapContinue(tester);
    expect(submitted.single, {'filePath': '/fake/captures/identification_card_2.jpg'});
  });

  testWidgets('backing out of the camera changes nothing', (tester) async {
    await tester.pumpWidget(stacStageApp(
      widgetJson: recordedStacWidget('identification_card'),
      submitted: submitted,
      media: media,
      pickPhoto: () async => null,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    expect(media.persistedCopies, isEmpty);
    expect(find.text('Take photo'), findsOneWidget);
  });

  group('camera permission outcomes (image_picker error codes)', () {
    Future<void> tapWithError(WidgetTester tester, PlatformException error) async {
      await tester.pumpWidget(stacStageApp(
        widgetJson: recordedStacWidget('identification_card'),
        submitted: submitted,
        media: media,
        pickPhoto: () async => throw error,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
    }

    testWidgets('camera_access_denied -> plain-language message, and the agent can try again', (tester) async {
      await tapWithError(tester, PlatformException(code: 'camera_access_denied'));

      expect(find.textContaining('Camera access is turned off for this app'), findsOneWidget);
      expect(find.text('Take photo'), findsOneWidget, reason: 'not stuck: they can enable it in Settings and retry');
      expect(submitted, isEmpty);
    });

    testWidgets('camera_access_restricted -> its own message', (tester) async {
      await tapWithError(tester, PlatformException(code: 'camera_access_restricted'));
      expect(find.textContaining('restricted on this device'), findsOneWidget);
    });

    testWidgets('any other platform error is a generic message, never a raw exception', (tester) async {
      await tapWithError(tester, PlatformException(code: 'weird', message: 'raw internal detail'));
      expect(find.text('Something unexpected happened. Please try again.'), findsOneWidget);
      expect(find.textContaining('raw internal detail'), findsNothing);
    });
  });
}
