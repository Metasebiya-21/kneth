import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/liveness/domain/device_liveness_assessment.dart';

Map<String, dynamic> _flags({
  bool motion = false,
  bool flash = false,
  bool depth = false,
  bool glare = false,
  bool contours = false,
}) =>
    {
      'screenGlareDetected': glare,
      'lackOfFacialContoursDetected': contours,
      'motionCorrelationCheckFailed': motion,
      'screenFlashSpoofDetected': flash,
      'depthSpoofDetected': depth,
    };

DeviceLivenessAssessment _assess(Map<String, dynamic>? flags, {bool packageOk = true}) =>
    assessDeviceLiveness(packageReportedSuccess: packageOk, antiSpoofingFlags: flags);

void main() {
  group('the decision: which flags block', () {
    test('all clear passes', () {
      final a = _assess(_flags());
      expect(a.verdict, isTrue);
      expect(a.blockingReasons, isEmpty);
      expect(a.informationalFlags, isEmpty);
    });

    test('motion correlation failure blocks', () {
      final a = _assess(_flags(motion: true));
      expect(a.verdict, isFalse);
      expect(a.blockingReasons, ['motionCorrelationCheckFailed']);
    });

    test('screen-flash and depth spoofing block too (only present if someone enables those detectors)', () {
      expect(_assess(_flags(flash: true)).blockingReasons, ['screenFlashSpoofDetected']);
      expect(_assess(_flags(depth: true)).blockingReasons, ['depthSpoofDetected']);
    });

    test('glare alone does NOT block; it is recorded as informational', () {
      final a = _assess(_flags(glare: true));
      expect(a.verdict, isTrue);
      expect(a.informationalFlags, ['screenGlareDetected']);
    });

    test('lack of facial contours alone does NOT block', () {
      final a = _assess(_flags(contours: true));
      expect(a.verdict, isTrue);
      expect(a.informationalFlags, ['lackOfFacialContoursDetected']);
    });

    test('both informational flags together still do not block', () {
      final a = _assess(_flags(glare: true, contours: true));
      expect(a.verdict, isTrue);
      expect(a.informationalFlags, ['screenGlareDetected', 'lackOfFacialContoursDetected']);
    });

    test('a blocking flag wins over informational ones, and both are reported', () {
      final a = _assess(_flags(motion: true, glare: true));
      expect(a.verdict, isFalse);
      expect(a.blockingReasons, ['motionCorrelationCheckFailed']);
      expect(a.informationalFlags, ['screenGlareDetected']);
    });

    test('every blocking flag at once are all listed', () {
      final a = _assess(_flags(motion: true, flash: true, depth: true));
      expect(a.blockingReasons, kBlockingAntiSpoofingFlags);
    });
  });

  group('fail closed', () {
    test('the package itself reporting failure blocks even with clean flags', () {
      final a = _assess(_flags(), packageOk: false);
      expect(a.verdict, isFalse);
      expect(a.blockingReasons, [kPackageReportedFailure]);
    });

    test('no metadata at all blocks', () {
      final a = _assess(null);
      expect(a.verdict, isFalse);
      expect(a.blockingReasons, contains(kMissingAntiSpoofingMetadata));
    });

    test('a missing blocking key blocks (only an explicit false passes)', () {
      final flags = _flags()..remove('motionCorrelationCheckFailed');
      final a = _assess(flags);
      expect(a.verdict, isFalse);
      expect(a.blockingReasons, ['motionCorrelationCheckFailed']);
    });

    test('a non-boolean blocking value blocks', () {
      final a = _assess({..._flags(), 'depthSpoofDetected': 'no'});
      expect(a.verdict, isFalse);
      expect(a.blockingReasons, ['depthSpoofDetected']);
    });

    test('a missing informational key is simply not reported and never blocks', () {
      final flags = _flags()
        ..remove('screenGlareDetected')
        ..remove('lackOfFacialContoursDetected');
      expect(_assess(flags).verdict, isTrue);
    });
  });

  group('guidance text', () {
    test('a motion failure tells the agent to hold the phone (the known false-positive)', () {
      expect(livenessFailureGuidance(_assess(_flags(motion: true))), contains('Hold the phone in your hand'));
    });

    test('other failures get a generic retry message', () {
      expect(livenessFailureGuidance(_assess(_flags(), packageOk: false)), contains('try again'));
    });

    test('tips exist only for informational flags, and never for a clean result', () {
      expect(livenessTips(_assess(_flags())), isEmpty);
      expect(livenessTips(_assess(_flags(glare: true))), hasLength(1));
      expect(livenessTips(_assess(_flags(glare: true, contours: true))), hasLength(2));
    });
  });
}
