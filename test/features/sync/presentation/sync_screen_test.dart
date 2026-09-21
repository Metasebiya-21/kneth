import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  }) {
    submitCaseCallCount++;
    lastCaseId = caseId;
    return Stream.fromIterable(statuses);
  }
}

void main() {
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
