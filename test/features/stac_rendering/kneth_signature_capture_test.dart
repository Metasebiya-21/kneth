// kneth_signature_capture — the widget the scoping doc explicitly did NOT
// prototype. These tests are the actual investigation:
//  1. does RenderRepaintBoundary.toImage()/toByteData() behave inside a
//     Stac-parsed tree the way it does in the old SignatureCaptureScreen
//     (including the documented testWidgets/runAsync gotcha)?  -> "export"
//  2. is the produced file a real PNG that contains the ink?   -> "PNG"
//  3. does a stroke inside a *scrolling* form survive the scroll view's own
//     drag recognizer?                                          -> "scroll"
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/native_capture/presentation/signature_painter.dart';

import 'stac_test_actions.dart';
import 'stac_test_harness.dart';

const _signatureJson = {'type': 'kneth_signature_capture', 'id': 'consent_signature', 'label': 'consent_signature'};

Finder get _canvas => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is SignaturePainter);

/// Taps Continue inside runAsync and waits (with real delays) until
/// [done] — the export's toByteData completes off the frame scheduler, so
/// plain pump()/pumpAndSettle() never observe it (the finding originally made
/// against the since-deleted SignatureCaptureScreen's test).
Future<void> _continueAndWait(WidgetTester tester, bool Function() done) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('Continue'));
    var attempts = 0;
    while (!done() && attempts < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      attempts++;
    }
  });
  await tester.pump();
}

void main() {
  testWidgets('export: Continue exports the canvas, persists via persistBytes, and submits {filePath: ...}',
      (tester) async {
    final media = FakeMediaStorageRepository();
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(stacStageApp(widgetJson: _signatureJson, submitted: submitted, media: media));
    await tester.pumpAndSettle();

    await tester.drag(_canvas, const Offset(120, 40));
    await tester.pump();

    await _continueAndWait(tester, () => submitted.isNotEmpty);

    expect(media.persistedBytes, hasLength(1));
    expect(submitted.single, {'filePath': '/fake/captures/consent_signature_1.png'});
  });

  testWidgets('PNG: the persisted bytes are a decodable PNG at 3x the canvas size and contain dark ink',
      (tester) async {
    final media = FakeMediaStorageRepository();
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(stacStageApp(widgetJson: _signatureJson, submitted: submitted, media: media));
    await tester.pumpAndSettle();
    final canvasSize = tester.getSize(_canvas);

    await tester.drag(_canvas, const Offset(120, 40));
    await tester.pump();
    await _continueAndWait(tester, () => submitted.isNotEmpty);

    final bytes = Uint8List.fromList(media.persistedBytes.single);
    expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10], reason: 'PNG signature');

    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, (canvasSize.width * 3).round());
      expect(image.height, (canvasSize.height * 3).round());
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var dark = 0;
      var white = 0;
      for (var i = 0; i < rgba.lengthInBytes; i += 4) {
        final r = rgba.getUint8(i);
        if (r < 60) dark++;
        if (r > 240) white++;
      }
      expect(dark, greaterThan(100), reason: 'the stroke must actually be in the exported image');
      expect(white, greaterThan(dark), reason: 'and the background is white');
    });
  });

  testWidgets('nothing drawn: Continue is blocked, no export happens', (tester) async {
    final media = FakeMediaStorageRepository();
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(stacStageApp(widgetJson: _signatureJson, submitted: submitted, media: media));
    await tester.pumpAndSettle();

    await tapContinue(tester);

    expect(find.text('Sign in the box to continue'), findsOneWidget);
    expect(media.persistedBytes, isEmpty);
    expect(submitted, isEmpty);
  });

  testWidgets('Clear empties the canvas and disables Clear again', (tester) async {
    await tester.pumpWidget(stacStageApp(widgetJson: _signatureJson, submitted: [], media: FakeMediaStorageRepository()));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Clear')).onPressed, isNull);

    await tester.drag(_canvas, const Offset(60, 0));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Clear')).onPressed, isNotNull);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Clear')).onPressed, isNull);
  });

  testWidgets('re-signing after a failed Continue replaces the exported file and deletes the previous one',
      (tester) async {
    final media = FakeMediaStorageRepository();
    final submitted = <Map<String, dynamic>>[];
    // A required text field alongside, so the first Continue exports but is blocked.
    await tester.pumpWidget(stacStageApp(
      widgetJson: {
        'type': 'column',
        'children': [
          {'type': 'kneth_text', 'id': 'name', 'label': 'name', 'required': true},
          _signatureJson,
        ],
      },
      submitted: submitted,
      media: media,
    ));
    await tester.pumpAndSettle();
    await tester.drag(_canvas, const Offset(80, 10));
    await tester.pump();

    await _continueAndWait(tester, () => media.persistedBytes.isNotEmpty);
    expect(submitted, isEmpty, reason: 'name is required');
    expect(media.persistedBytes, hasLength(1));

    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tester.drag(_canvas, const Offset(-60, 20));
    await tester.pump();
    await tester.enterText(textFieldLabelled('name'), 'Ada');
    await _continueAndWait(tester, () => submitted.isNotEmpty);

    expect(media.persistedBytes, hasLength(2));
    expect(media.deleted, ['/fake/captures/consent_signature_1.png']);
    expect(submitted.single['filePath'], '/fake/captures/consent_signature_2.png');
  });

  group('scroll: a stroke inside a scrolling form', () {
    // Many small moves, like a finger. (Measured while writing this: with a
    // plain GestureDetector(onPan...) the scroll view receives the drag and
    // the pan callbacks get zero events, whether the drag is one big move or
    // many small ones.)
    Future<void> fingerDragUp(WidgetTester tester, Finder target) async {
      final gesture = await tester.startGesture(tester.getCenter(target));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, -5));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pump();
    }

    testWidgets('CONTROL: a plain GestureDetector(onPan...) inside a scroll view loses vertical drags to the scroll',
        (tester) async {
      var panUpdates = 0;
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              const SizedBox(height: 300),
              SizedBox(
                key: key,
                height: 200,
                width: double.infinity,
                child: GestureDetector(onPanUpdate: (_) => panUpdates++, child: const ColoredBox(color: Colors.white)),
              ),
              const SizedBox(height: 1500),
            ]),
          ),
        ),
      ));
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);

      await fingerDragUp(tester, find.byKey(key));

      expect(scrollable.position.pixels, greaterThan(0), reason: 'the scroll view won the arena');
      expect(panUpdates, 0, reason: 'so a plain pan-based canvas would have lost the stroke');
    });

    testWidgets('kneth_signature_capture claims the pointer: the form does not scroll and the stroke is recorded',
        (tester) async {
      await tester.pumpWidget(stacStageApp(
        widgetJson: {
          'type': 'column',
          'children': [
            {'type': 'sizedBox', 'height': 100},
            _signatureJson,
            {'type': 'sizedBox', 'height': 1500},
          ],
        },
        submitted: [],
        media: FakeMediaStorageRepository(),
      ));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Clear')).onPressed, isNull);

      await fingerDragUp(tester, _canvas);

      expect(scrollable.position.pixels, 0, reason: 'a vertical stroke must not scroll the form');
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Clear')).onPressed, isNotNull,
          reason: 'and the stroke was recorded');
    });
  });
}
