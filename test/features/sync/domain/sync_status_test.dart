// A pure-Dart unit test — no Flutter widgets involved, so plain
// package:test (via flutter_test, which just re-exports it) is enough.
// This is the whole point of keeping domain/ framework-free: these tests
// run in milliseconds with no widget tree, no bindings, nothing.
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/sync/domain/sync_status.dart';
import 'package:sdui_demo/services/app_exception.dart';

void main() {
  test('SyncUploading carries its step, totalSteps, and label', () {
    const status = SyncUploading(step: 1, totalSteps: 2, label: 'Submitting case');

    expect(status.step, 1);
    expect(status.totalSteps, 2);
    expect(status.label, 'Submitting case');
  });

  test('SyncFailed carries its exception', () {
    const status = SyncFailed(NetworkException());

    expect(status.exception, isA<NetworkException>());
  });

  test('every state is a SyncStatus, distinguishable with a switch', () {
    // This is really testing the sealed class itself: a switch over
    // SyncStatus with every subtype covered needs no `default` case (the
    // analyzer enforces exhaustiveness), which is what lets SyncScreen's
    // `switch (status) { ... }` be trusted to handle every case.
    String describe(SyncStatus status) => switch (status) {
          SyncIdle() => 'idle',
          SyncUploading() => 'uploading',
          SyncSucceeded() => 'succeeded',
          SyncFailed() => 'failed',
        };

    expect(describe(const SyncIdle()), 'idle');
    expect(describe(const SyncUploading(step: 1, totalSteps: 2, label: 'x')), 'uploading');
    expect(describe(const SyncSucceeded()), 'succeeded');
    expect(describe(const SyncFailed(NetworkException())), 'failed');
  });
}
