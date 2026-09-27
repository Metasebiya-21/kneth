import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

/// DEBUG BUILDS ONLY — see network_log.dart's header.
///
/// One accelerometer reading with gravity already removed, in m/s².
typedef Acceleration = ({double x, double y, double z});

/// Calls [onShake] for a deliberate shake: [joltsNeeded] readings above
/// [threshold] within [window], then quiet for [cooldown]. One jolt alone
/// (setting the phone down hard, a bump in a pocket) doesn't count.
///
/// Uses `sensors_plus`' user accelerometer (gravity removed) — already in
/// the dependency tree through `smart_liveliness_detection`, at the same
/// version range, rather than adding a shake package on top of it. Takes
/// its readings as a plain stream so tests can script them.
class ShakeDetector {
  final void Function() onShake;
  final double threshold;
  final int joltsNeeded;
  final Duration window;
  final Duration cooldown;
  final DateTime Function() _now;

  StreamSubscription<Acceleration>? _subscription;
  final List<DateTime> _jolts = [];
  DateTime? _quietUntil;

  ShakeDetector({
    required this.onShake,
    this.threshold = 15,
    this.joltsNeeded = 3,
    this.window = const Duration(milliseconds: 1000),
    this.cooldown = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  void start([Stream<Acceleration>? readings]) {
    stop();
    _subscription = (readings ?? _deviceReadings()).listen(handle, onError: (_) {
      // No accelerometer (an emulator without one, a desktop build): no
      // shake, nothing else affected.
    });
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void handle(Acceleration a) {
    final now = _now();
    final quietUntil = _quietUntil;
    if (quietUntil != null && now.isBefore(quietUntil)) return;
    if (sqrt(a.x * a.x + a.y * a.y + a.z * a.z) < threshold) return;
    _jolts
      ..add(now)
      ..removeWhere((t) => now.difference(t) > window);
    if (_jolts.length >= joltsNeeded) {
      _jolts.clear();
      _quietUntil = now.add(cooldown);
      onShake();
    }
  }

  static Stream<Acceleration> _deviceReadings() => userAccelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).map((e) => (x: e.x, y: e.y, z: e.z));
}
