import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/sync/data/sync_repository_impl.dart';
import 'package:sdui_demo/features/sync/domain/sync_repository.dart';
import 'package:sdui_demo/features/sync/domain/sync_status.dart';
import 'package:sdui_demo/features/sync/presentation/sync_screen.dart';
import 'package:sdui_demo/services/app_exception.dart';

import '../../../support/fake_api_client.dart';
import '../../../support/fake_flow_session.dart';

/// A fake at the domain boundary: no ApiClient, no network mock, just
/// hands back whatever [statuses] the test wants — this is what lets the
/// widget test check SyncScreen's rendering/wiring in isolation from
/// SyncRepositoryImpl entirely.
class _FakeSyncRepository implements SyncRepository {
  _FakeSyncRepository(this.statuses);

  final List<SyncStatus> statuses;
  int submitCaseCallCount = 0;

  String? lastCaseId;

  @override
  Stream<SyncStatus> submitCase({
    required String? caseId,
    required Map<String, dynamic> values,
    required Map<String, String> mediaFilesByStage,
    Map<String, Map<String, dynamic>> attestedLivenessByStage = const {},
  }) {
    submitCaseCallCount++;
    lastCaseId = caseId;
    return Stream.fromIterable(statuses);
  }
}

void main() {
  // Regression, found on a real device: in the app SyncScreen sits UNDER
  // main.dart's root ProviderScope, so its own ProviderScope is a nested one.
  // syncNotifierProvider must declare syncRepositoryProvider as a dependency
  // or Riverpod resolves it in the root scope, where the repository was never
  // overridden ("syncRepositoryProvider has no default"). Every other test
  // here pumps SyncScreen with no outer scope, which is why none caught it.
  testWidgets('works nested under an app-level ProviderScope, as in main.dart', (tester) async {
    final session = FakeFlowSession(apiClient: FakeApiClient());
    final repository = _FakeSyncRepository([const SyncSucceeded()]);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: SyncScreen(controller: session, repository: repository))),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(repository.submitCaseCallCount, 1);
    expect(find.text('Case synced successfully'), findsOneWidget);
  });

  testWidgets('renders progress from the injected repository, then success', (tester) async {
    final session = FakeFlowSession(apiClient: FakeApiClient());
    final repository = _FakeSyncRepository([
      const SyncUploading(step: 1, totalSteps: 2, label: 'Submitting case'),
      const SyncUploading(step: 2, totalSteps: 2, label: 'Processing'),
      const SyncSucceeded(),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: SyncScreen(controller: session, repository: repository)),
    );
    await tester.pump(); // let the stream's first event land
    await tester.pump();
    await tester.pump();

    expect(repository.submitCaseCallCount, 1);
    // The flow session's own caseId reaches the repository call — not
    // dropped or hardcoded null (see NOTES.md's Phase 1).
    expect(repository.lastCaseId, session.caseId);
    expect(find.text('Case synced successfully'), findsOneWidget);
    // SyncSucceeded should have told the flow session to clear its saved
    // state — no need to resume a case that's already synced.
    expect(session.clearSavedCallCount, 1);
  });

  testWidgets(
      'end to end through the real SyncRepositoryImpl: an individual and a business capture reach their own endpoints',
      (tester) async {
    final api = FakeApiClient()
      ..recordIdToReturn = 'record-1'
      ..businessRecordIdToReturn = 'business-1';
    final session = FakeFlowSession(apiClient: api, allValues: const {
      'personal_info.full_name': 'Ada',
      'business_info.business_name': 'Ada Ltd',
      'identification_card.filePath': '/tmp/id.jpg',
      'trade_license.filePath': '/tmp/license.jpg',
    });

    await tester.pumpWidget(
      MaterialApp(home: SyncScreen(controller: session, repository: SyncRepositoryImpl(apiClient: api))),
    );
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();

    expect(find.text('Case synced successfully'), findsOneWidget);
    expect(api.uploadDocumentCalls.map((c) => '${c['recordId']}/${c['kind']}'), ['record-1/identification_card']);
    expect(api.uploadBusinessDocumentCalls.map((c) => '${c['businessRecordId']}/${c['kind']}'),
        ['business-1/trade_license']);
  });

  testWidgets('the screen hands the repository each stage\'s attested liveness claim and its image', (tester) async {
    final api = FakeApiClient()..recordIdToReturn = 'record-1';
    final session = FakeFlowSession(apiClient: api, allValues: const {
      'personal_info.full_name': 'Ada',
      'selfie_liveness.filePath': '/tmp/selfie.jpg',
      'selfie_liveness.attestedLiveness': {
        'attestedLivenessVerdict': true,
        'attestedAntiSpoofingFlags': {'motionCorrelationCheckFailed': false},
        'attestedSessionId': 's-1',
        'attestedDetector': 'smart_liveliness_detection 0.3.9',
        'attestedAttemptsUsed': 1,
      },
    });

    await tester.pumpWidget(
      MaterialApp(home: SyncScreen(controller: session, repository: SyncRepositoryImpl(apiClient: api))),
    );
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();

    expect(find.text('Case synced successfully'), findsOneWidget);
    expect(api.uploadDocumentCalls.single['kind'], 'profile_picture');
    expect(api.submitAttestedLivenessCalls.single['attestedLivenessVerdict'], true);
    expect(api.submitAttestedLivenessCalls.single['recordId'], 'record-1');
  });

  testWidgets('retry re-submits through the same injected repository', (tester) async {
    final session = FakeFlowSession(apiClient: FakeApiClient());
    final repository = _FakeSyncRepository([const SyncFailed(NetworkException())]);

    await tester.pumpWidget(
      MaterialApp(home: SyncScreen(controller: session, repository: repository)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('offline'), findsOneWidget);
    expect(repository.submitCaseCallCount, 1);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
    await tester.pump();
    await tester.pump();

    expect(repository.submitCaseCallCount, 2);
  });
}
