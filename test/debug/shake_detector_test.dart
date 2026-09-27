import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/debug/shake_detector.dart';

void main() {
  late DateTime now;
  late int shakes;
  late ShakeDetector detector;

  setUp(() {
    now = DateTime(2026, 9, 27, 12);
    shakes = 0;
    detector = ShakeDetector(onShake: () => shakes++, now: () => now);
  });

  void jolt({double g = 20, int afterMs = 100}) {
    now = now.add(Duration(milliseconds: afterMs));
    detector.handle((x: g, y: 0, z: 0));
  }

  test('three strong jolts within a second is a shake', () {
    jolt();
    jolt();
    expect(shakes, 0);
    jolt();
    expect(shakes, 1);
  });

  test('one hard bump, or gentle movement, is not', () {
    jolt();
    for (var i = 0; i < 10; i++) {
      jolt(g: 5);
    }
    expect(shakes, 0);
  });

  test('jolts spread over more than the window do not add up', () {
    jolt();
    jolt(afterMs: 700);
    jolt(afterMs: 700);
    expect(shakes, 0);
  });

  test('after a shake, it stays quiet for the cooldown', () {
    jolt();
    jolt();
    jolt();
    jolt();
    jolt();
    jolt();
    expect(shakes, 1);
    jolt(afterMs: 2500);
    jolt();
    jolt();
    expect(shakes, 2);
  });

  test('start() listens to a supplied stream (and stop() detaches)', () async {
    final readings = Stream<Acceleration>.fromIterable(List.filled(3, (x: 0.0, y: 20.0, z: 0.0)));
    final live = ShakeDetector(onShake: () => shakes++);
    live.start(readings);
    await Future<void>.delayed(Duration.zero);
    expect(shakes, 1);
    live.stop();
  });
}
