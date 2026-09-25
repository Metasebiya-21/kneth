// kneth_liveness_capture against the real recorded selfie_liveness stage (the backend's own
// serializer output for a NATIVE_CAPTURE stage with native_handler `liveness_capture`).
//
// TWO THINGS ARE FAKED. The camera flow is faked at the CaptureLiveness seam, and the backend's
// per-case attempt count is a scripted FakeApiClient. Every test here proves only this widget's
// own handling of what those hand back. NONE of it is evidence that the detection works (the
// camera stream, ML Kit, the accelerometer behind motion correlation, glare/contour detection
// need a real device, face and light), nor that the backend counts correctly: that is the
// backend's own unit/integration tests and the live tests. In particular the motion-correlation
// false positive (a phone propped on a table while a real person turns their head) cannot be
// observed without hardware.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/liveness/domain/liveness_capture_result.dart';
import 'package:sdui_demo/features/liveness/presentation/liveness_capture_screen.dart' show kLivenessConfig;
import 'package:sdui_demo/features/stac_rendering/presentation/parsers/kneth_photo_capture_parser.dart'
    show kCapturedFilePathKey;
import 'package:sdui_demo/services/api_dtos.dart';
import 'package:sdui_demo/services/app_exception.dart';

import '../../support/fake_api_client.dart';
import '../../support/stac_fixtures.dart';
import 'stac_test_actions.dart';
import 'stac_test_harness.dart';

const _clean = {
  'screenGlareDetected': false,
  'lackOfFacialContoursDetected': false,
  'motionCorrelationCheckFailed': false,
  'screenFlashSpoofDetected': false,
  'depthSpoofDetected': false,
};

LivenessCaptureResult _result({
  bool packageOk = true,
  Map<String, dynamic>? flags = _clean,
  String? image = '/cache/selfie.jpg',
  String session = 'session-1',
}) =>
    LivenessCaptureResult(
      sessionId: session,
      packageReportedSuccess: packageOk,
      antiSpoofingFlags: flags,
      imagePath: image,
    );

void main() {
  test('none of the package\'s status texts we show says "verification": the device only makes a claim', () {
    final m = kLivenessConfig.messages;
    for (final text in [m.processingVerification, m.verificationComplete, m.spoofingDetected, m.screenFlashSpoofingDetected]) {
      expect(text.toLowerCase(), isNot(contains('verif')), reason: text);
    }
  });

  late FakeMediaStorageRepository media;
  late FakeApiClient api;
  late List<Map<String, dynamic>> submitted;

  setUp(() {
    media = FakeMediaStorageRepository();
    api = FakeApiClient();
    submitted = [];
  });

  Future<void> pump(WidgetTester tester, Future<LivenessCaptureResult?> Function(BuildContext) launcher,
      {Map<String, dynamic> initialValues = const {}}) async {
    await tester.pumpWidget(stacStageApp(
      widgetJson: recordedStacWidget('selfie_liveness'),
      submitted: submitted,
      media: media,
      apiClient: api,
      captureLiveness: launcher,
      initialValues: initialValues,
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('the real recorded selfie_liveness stage renders through kneth_liveness_capture', (tester) async {
    expect(recordedStacWidget('selfie_liveness')['type'], 'kneth_liveness_capture');
    await pump(tester, (_) async => null);
    expect(find.text('Start selfie check'), findsOneWidget);
    expect(api.fetchLivenessStatusCallCount, 1, reason: 'asks the backend where the case stands on mount');
  });

  testWidgets('Continue is blocked until the selfie check is done', (tester) async {
    await pump(tester, (_) async => null);
    await tapContinue(tester);
    expect(find.text('Complete the selfie check to continue'), findsOneWidget);
    expect(submitted, isEmpty);
  });

  testWidgets('a pass: the attempt is started and reported to the backend, then image and claim are stored',
      (tester) async {
    await pump(tester, (_) async => _result());
    await tapText(tester, 'Start selfie check');

    expect(api.beginLivenessCallCount, 1);
    expect(api.recordedLivenessOutcomes.single['attestedLivenessVerdict'], true);
    expect(api.recordedLivenessOutcomes.single['caseId'], 'case-1');
    expect(find.text('Selfie check complete'), findsOneWidget);
    expect(find.textContaining('reported by this device'), findsOneWidget);
    expect(find.textContaining('erified'), findsNothing, reason: 'no label may say verified');

    await tapContinue(tester);
    final values = submitted.single;
    expect(values[kCapturedFilePathKey], '/fake/captures/selfie_liveness_1.jpg');
    final claim = values[kAttestedLivenessKey] as Map<String, dynamic>;
    expect(claim, {
      'attestedLivenessVerdict': true,
      'attestedAntiSpoofingFlags': _clean,
      'attestedSessionId': 'session-1',
      'attestedDetector': kLivenessDetector,
      'attestedAttemptsUsed': 1,
    });
  });

  testWidgets('glare alone does not block: the check passes and shows a tip', (tester) async {
    await pump(tester, (_) async => _result(flags: {..._clean, 'screenGlareDetected': true}));
    await tapText(tester, 'Start selfie check');
    expect(find.text('Selfie check complete'), findsOneWidget);
    expect(find.textContaining('Tip:'), findsOneWidget);
    await tapContinue(tester);
    expect(submitted, hasLength(1));
  });

  testWidgets('a motion-correlation failure is reported as a failed attempt, with guidance and the BACKEND\'s count',
      (tester) async {
    await pump(tester, (_) async => _result(flags: {..._clean, 'motionCorrelationCheckFailed': true}));
    await tapText(tester, 'Start selfie check');

    expect(api.recordedLivenessOutcomes.single['attestedLivenessVerdict'], false);
    expect(find.textContaining('Hold the phone in your hand'), findsOneWidget);
    expect(find.text('Tries left: 2'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tapContinue(tester);
    expect(submitted, isEmpty);
  });

  testWidgets('three failures: the case goes to manual review, with a plain message and no way to continue',
      (tester) async {
    var calls = 0;
    await pump(tester, (_) async {
      calls++;
      return _result(packageOk: false);
    });
    await tapText(tester, 'Start selfie check');
    await tapText(tester, 'Try again');
    expect(find.text('Tries left: 1'), findsOneWidget);
    await tapText(tester, 'Try again');

    expect(calls, 3);
    expect(find.text('Try again'), findsNothing);
    expect(find.textContaining('sent to a supervisor for manual review'), findsOneWidget);
    expect(find.text('Check review status'), findsOneWidget);
    await tapContinue(tester);
    expect(find.text('The selfie check is waiting for a supervisor'), findsOneWidget);
    expect(submitted, isEmpty);
  });

  testWidgets('FORCE-QUIT: a relaunch after the backend has counted three attempts shows the hard stop at once, '
      'and the device could not have started a fourth', (tester) async {
    // A previous app session used up the attempts; this "relaunch" has no local state at all.
    api.livenessAttempts.addAll([false, false, false]);
    var launched = 0;
    await pump(tester, (_) async {
      launched++;
      return _result();
    });

    expect(find.textContaining('sent to a supervisor for manual review'), findsOneWidget);
    expect(find.text('Start selfie check'), findsNothing);
    expect(launched, 0);

    // And even if the status call had failed on mount (start button shown), the backend refuses the fourth.
    api.fetchLivenessStatusError = const NetworkException();
    await tester.pumpWidget(const SizedBox()); // a genuinely new screen, no widget state carried over
    await pump(tester, (_) async {
      launched++;
      return _result();
    });
    expect(find.text('Start selfie check'), findsOneWidget);
    api.fetchLivenessStatusError = null;
    await tapText(tester, 'Start selfie check');
    expect(launched, 0, reason: 'the backend answered 409, so the camera never opened');
    expect(find.textContaining('sent to a supervisor for manual review'), findsOneWidget);
  });

  testWidgets('a relaunch mid-way shows the backend\'s remaining tries, not a fresh three', (tester) async {
    api.livenessAttempts.addAll([false, false]);
    await pump(tester, (_) async => null);
    expect(find.text('Tries left: 1'), findsOneWidget);
    await tapText(tester, 'Try again');
    // begin started the third attempt and the camera was backed out of.
    expect(api.livenessAttempts, [false, false, null]);
    await tapText(tester, 'Try again');
    expect(api.livenessAttempts, [false, false, null], reason: 'the open attempt is reused, not duplicated');
  });

  testWidgets('backing out of the camera screen does not report an outcome', (tester) async {
    await pump(tester, (_) async => null);
    await tapText(tester, 'Start selfie check');
    expect(api.beginLivenessCallCount, 1);
    expect(api.recordLivenessOutcomeCallCount, 0);
    expect(find.text('Start selfie check'), findsOneWidget);
  });

  testWidgets('a pass with no captured image is reported as a failed attempt', (tester) async {
    await pump(tester, (_) async => _result(image: null));
    await tapText(tester, 'Start selfie check');
    expect(api.recordedLivenessOutcomes.single['attestedLivenessVerdict'], false);
    expect(find.textContaining('photo was not captured'), findsOneWidget);
    await tapContinue(tester);
    expect(submitted, isEmpty);
  });

  testWidgets('a failed attempt then a pass: the pass is recorded with the attempts it took', (tester) async {
    var calls = 0;
    await pump(tester, (_) async => ++calls == 1 ? _result(packageOk: false) : _result(session: 'session-2'));
    await tapText(tester, 'Start selfie check');
    await tapText(tester, 'Try again');
    await tapContinue(tester);
    final claim = submitted.single[kAttestedLivenessKey] as Map<String, dynamic>;
    expect(claim['attestedSessionId'], 'session-2');
    expect(claim['attestedAttemptsUsed'], 2);
  });

  testWidgets('if the outcome cannot be reported the result is kept and retried, without a second camera session',
      (tester) async {
    var launched = 0;
    await pump(tester, (_) async {
      launched++;
      return _result(packageOk: false);
    });
    api.recordLivenessOutcomeError = const NetworkException();
    await tapText(tester, 'Start selfie check');
    expect(find.textContaining('offline'), findsOneWidget);
    expect(find.text('Send result again'), findsOneWidget);

    api.recordLivenessOutcomeError = null;
    await tapText(tester, 'Send result again');
    expect(launched, 1, reason: 'the camera flow is not repeated');
    expect(api.recordedLivenessOutcomes, hasLength(1));
    expect(find.text('Tries left: 2'), findsOneWidget);
  });

  testWidgets('no connection when starting: the camera does not open (the backend must count the attempt)',
      (tester) async {
    var launched = 0;
    await pump(tester, (_) async {
      launched++;
      return _result();
    });
    api.beginLivenessError = const NetworkException();
    await tapText(tester, 'Start selfie check');
    expect(launched, 0);
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('an unavailable camera surfaces through AppErrorView', (tester) async {
    await pump(tester, (_) async => throw const ForbiddenException('The camera is not available.'));
    await tapText(tester, 'Start selfie check');
    expect(find.text('The camera is not available.'), findsOneWidget);
    expect(find.text('Start selfie check'), findsOneWidget, reason: 'the agent can try again');
  });

  testWidgets('a resumed case that already holds a passed check keeps it', (tester) async {
    await pump(tester, (_) async => null, initialValues: {
      kCapturedFilePathKey: '/fake/captures/selfie_liveness_1.jpg',
      kAttestedLivenessKey: {'attestedLivenessVerdict': true},
    });
    expect(find.text('Selfie check complete'), findsOneWidget);
    expect(api.fetchLivenessStatusCallCount, 0);
    await tapContinue(tester);
    expect(submitted, hasLength(1));
  });

  group('manual review', () {
    testWidgets('waiting: "Check review status" asks the backend again and keeps waiting while undecided',
        (tester) async {
      api.livenessAttempts.addAll([false, false, false]);
      await pump(tester, (_) async => null);
      final before = api.fetchLivenessStatusCallCount;
      await tapText(tester, 'Check review status');
      expect(api.fetchLivenessStatusCallCount, before + 1);
      expect(find.textContaining('sent to a supervisor for manual review'), findsOneWidget);
      await tapContinue(tester);
      expect(submitted, isEmpty);
    });

    testWidgets('a supervisor\'s acceptance completes the stage with nothing to upload and no attested claim',
        (tester) async {
      api.livenessAttempts.addAll([false, false, false]);
      await pump(tester, (_) async => null);
      api
        ..livenessCaseStatusForced = 'in_progress'
        ..livenessOverride = const LivenessOverrideDto(method: 'physical_document_review', decision: 'accepted');
      await tapText(tester, 'Check review status');

      expect(find.text('Approved by manual review'), findsOneWidget);
      await tapContinue(tester);
      final values = submitted.single;
      expect(values[kLivenessManualOverrideKey], {'method': 'physical_document_review', 'decision': 'accepted'});
      expect(values.containsKey(kCapturedFilePathKey), isFalse, reason: 'no selfie exists, so nothing is uploaded');
      expect(values.containsKey(kAttestedLivenessKey), isFalse, reason: 'nothing was attested; a human decided');
    });

    testWidgets('a supervisor\'s acceptance is picked up on relaunch too', (tester) async {
      api
        ..livenessAttempts.addAll([false, false, false])
        ..livenessCaseStatusForced = 'in_progress'
        ..livenessOverride = const LivenessOverrideDto(method: 'physical_document_review', decision: 'accepted');
      await pump(tester, (_) async => null);
      expect(find.text('Approved by manual review'), findsOneWidget);
    });

    testWidgets('a rejection leaves the case declined and the stage blocked', (tester) async {
      api
        ..livenessAttempts.addAll([false, false, false])
        ..livenessCaseStatusForced = 'rejected'
        ..livenessOverride = const LivenessOverrideDto(method: 'physical_document_review', decision: 'rejected');
      await pump(tester, (_) async => null);
      expect(find.textContaining('declined after manual review'), findsOneWidget);
      await tapContinue(tester);
      expect(submitted, isEmpty);
    });
  });
}
