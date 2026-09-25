// Shared machinery for the scripted Stac-flow scenarios (test/features/stac_rendering/
// stac_scenarios_test.dart offline, test/live/stac_live_test.dart against the real
// backend). Each scenario drives the real FlowScreen with the same finders and
// produces an observation log plus the flat payload the flow collected. These
// scenarios began life as the old-renderer-vs-Stac parity comparison; the old
// renderer is gone, and its recorded behavior lives on as golden files
// (test/fixtures/golden/, STAC_MIGRATION_SCOPING.md section 14.5).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/flow/data/stac_manifest_mapper.dart';
import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/presentation/flow_notifier.dart';
import 'package:sdui_demo/features/flow/presentation/flow_screen.dart';
import 'package:sdui_demo/services/api_client.dart';
import 'package:sdui_demo/services/api_dtos.dart';
import 'package:sdui_demo/services/app_exception.dart';

import 'fake_api_client.dart';
import 'fake_flow_repository.dart';

/// What one scripted run produced.
class ScenarioRun {
  final List<String> log = [];

  /// Exact validation messages etc., kept out of the log so tests can assert
  /// them (and compare them with the recorded goldens) separately.
  final Map<String, String> notes = {};
  Map<String, dynamic> allValues = const {};
  bool completed = false;

}

/// Mirrors what `dynamic_options_adapter.py` does with a live-options
/// request (read from the backend source): the `region` dependency must be a
/// UUID — the parent option's real value — or the request is rejected (422).
/// Used only for the OFFLINE tier; the live tier asks the real backend.
class BackendRulesApiClient extends FakeApiClient {
  BackendRulesApiClient({super.stacStages, super.optionsByEndpoint});

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');

  @override
  Future<List<FieldOptionDto>> fetchOptions({
    required String clientId,
    required String workflowId,
    required String fieldKey,
    required Map<String, String> dependencyValues,
  }) {
    if (fieldKey == 'district' && !_uuid.hasMatch(dependencyValues['region'] ?? '')) {
      fetchOptionsCallCount++;
      fetchOptionsFieldKeys.add(fieldKey);
      fetchOptionsDependencyValues.add(dependencyValues);
      throw ClientException(422, "dependency 'region' must be a UUID, got ${dependencyValues['region']}");
    }
    return super.fetchOptions(
      clientId: clientId,
      workflowId: workflowId,
      fieldKey: fieldKey,
      dependencyValues: dependencyValues,
    );
  }
}

/// Counts calls that are still in flight, so a live-tier test can wait for
/// real network I/O to finish instead of guessing a delay.
class InFlightCountingApiClient implements ApiClient {
  final ApiClient inner;
  int inFlight = 0;
  final List<String> calls = [];

  /// Every error a call threw, keyed by call name — lets a live test assert
  /// what the real backend actually answered.
  final Map<String, List<Object>> errors = {};

  InFlightCountingApiClient(this.inner);

  Future<T> _track<T>(String name, Future<T> Function() call) async {
    inFlight++;
    calls.add(name);
    try {
      return await call();
    } catch (e) {
      (errors[name] ??= []).add(e);
      rethrow;
    } finally {
      inFlight--;
    }
  }

  @override
  Future<StacFlowManifestDto> fetchFlowManifestStac({required String flowId, required String clientId, String? caseId}) =>
      _track('fetchFlowManifestStac', () => inner.fetchFlowManifestStac(flowId: flowId, clientId: clientId, caseId: caseId));

  @override
  Future<List<FieldOptionDto>> fetchOptions({
    required String clientId,
    required String workflowId,
    required String fieldKey,
    required Map<String, String> dependencyValues,
  }) =>
      _track('fetchOptions:$fieldKey', () => inner.fetchOptions(
            clientId: clientId,
            workflowId: workflowId,
            fieldKey: fieldKey,
            dependencyValues: dependencyValues,
          ));

  @override
  Future<SubmitCaseResultDto> submitCase({required String? caseId, required Map<String, dynamic> values}) =>
      _track('submitCase', () => inner.submitCase(caseId: caseId, values: values));

  @override
  Future<UploadedDocumentDto> uploadDocument({required String recordId, required String kind, required String filePath}) =>
      _track('uploadDocument', () => inner.uploadDocument(recordId: recordId, kind: kind, filePath: filePath));

  @override
  Future<LivenessStatusDto> fetchLivenessStatus(String caseId) =>
      _track('fetchLivenessStatus', () => inner.fetchLivenessStatus(caseId));

  @override
  Future<LivenessAttemptDto> beginLivenessAttempt(String caseId) =>
      _track('beginLivenessAttempt', () => inner.beginLivenessAttempt(caseId));

  @override
  Future<LivenessStatusDto> recordLivenessAttemptOutcome({
    required String caseId,
    required String attemptId,
    required bool attestedLivenessVerdict,
    required Map<String, dynamic> attestedAntiSpoofingFlags,
    String? attestedSessionId,
  }) =>
      _track(
          'recordLivenessAttemptOutcome',
          () => inner.recordLivenessAttemptOutcome(
                caseId: caseId,
                attemptId: attemptId,
                attestedLivenessVerdict: attestedLivenessVerdict,
                attestedAntiSpoofingFlags: attestedAntiSpoofingFlags,
                attestedSessionId: attestedSessionId,
              ));

  @override
  Future<AttestedLivenessResultDto> submitAttestedLiveness({
    required String recordId,
    required bool attestedLivenessVerdict,
    required Map<String, dynamic> attestedAntiSpoofingFlags,
    String? attestedSessionId,
    String? attestedDetector,
  }) =>
      _track(
          'submitAttestedLiveness',
          () => inner.submitAttestedLiveness(
                recordId: recordId,
                attestedLivenessVerdict: attestedLivenessVerdict,
                attestedAntiSpoofingFlags: attestedAntiSpoofingFlags,
                attestedSessionId: attestedSessionId,
                attestedDetector: attestedDetector,
              ));

  @override
  Future<UploadedDocumentDto> uploadBusinessDocument(
          {required String businessRecordId, required String kind, required String filePath}) =>
      _track('uploadBusinessDocument',
          () => inner.uploadBusinessDocument(businessRecordId: businessRecordId, kind: kind, filePath: filePath));

  @override
  Future<List<ClientSummaryDto>> fetchClients() => _track('fetchClients', inner.fetchClients);

  @override
  Future<List<WorkflowSummaryDto>> fetchWorkflows(String clientId) =>
      _track('fetchWorkflows', () => inner.fetchWorkflows(clientId));
}

/// Waits for a live-tier network call to finish. Real socket I/O only
/// progresses while the test yields to the real event loop (runAsync); the
/// continuation microtasks then run on the next pump.
Future<void> settle(WidgetTester tester, {InFlightCountingApiClient? live}) async {
  if (live != null) {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
      if (live.inFlight == 0) break;
    }
  }
  await tester.pumpAndSettle();
}

/// A flow already positioned at the first of [stacStages] (Stac-shaped, mapped exactly as
/// production maps them, via `stacStagesToStageJson`),
/// resumed rather than fetched, so a run starts at the stage under test.
Widget stacFlowApp({
  required ApiClient apiClient,
  required List<Map<String, dynamic>> stacStages,
  required String workflowId,
  required String clientId,
  required String caseId,
}) {
  final manifest = ResolvedFlowManifest(
    workflowId: workflowId,
    clientId: clientId,
    caseId: caseId,
    fetchedAt: DateTime.now(),
    stagesJson: stacStagesToStageJson(stacStages),
  );
  final repository = FakeFlowRepository(
    saved: FlowCaseState(manifest: manifest, stageIndex: 0, isComplete: false, collectedValues: const {}),
  );
  return ProviderScope(
    // A fresh scope per run: two runs in one test would otherwise reuse the
    // first run's container (same widget shape) and inherit its completed flow.
    key: UniqueKey(),
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      flowRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: FlowScreen(manifest: FlowManifest(workflowId: workflowId, clientId: clientId), resumeMode: true),
    ),
  );
}

FlowViewState flowState(WidgetTester tester) {
  final container = ProviderScope.containerOf(tester.element(find.byType(FlowScreen)));
  return container.read(flowNotifierProvider);
}

void captureResult(WidgetTester tester, ScenarioRun run) {
  final state = flowState(tester);
  if (state is FlowViewReady) {
    run.allValues = state.caseState.allValues;
    run.completed = state.caseState.isComplete;
  }
}

// ---- scripted interaction primitives, renderer-neutral finders --------

Finder textFieldWith(String label) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

bool isShown(String textFieldLabel) => textFieldWith(textFieldLabel).evaluate().isNotEmpty;

bool hasText(String text) => find.text(text).evaluate().isNotEmpty;

Future<void> choose(WidgetTester tester, String optionLabel, {required int dropdown, InFlightCountingApiClient? live}) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).at(dropdown));
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await settle(tester, live: live);
}

/// The option labels a dropdown offers right now (opens and closes it).
/// Items already on screen before opening (a closed dropdown displays its
/// selected item) are subtracted, so only the popup's own items remain; a
/// disabled dropdown (no items) therefore yields [].
Future<List<String>> optionsOf(WidgetTester tester, {required int dropdown}) async {
  List<String> items() => [
        for (final item in find.byType(DropdownMenuItem<String>).evaluate())
          ((item.widget as DropdownMenuItem<String>).child as Text).data!,
      ];
  final before = items();
  await tester.tap(find.byType(DropdownButtonFormField<String>).at(dropdown));
  await tester.pumpAndSettle();
  final popup = [...items()];
  for (final b in before) {
    popup.remove(b);
  }
  await tester.tapAt(const Offset(5, 5)); // dismiss the menu, if one opened
  await tester.pumpAndSettle();
  return popup.toSet().toList()..sort();
}

/// The text of the first visible Text matching [pattern], or null.
String? textMatching(RegExp pattern) {
  for (final e in find.byType(Text).evaluate()) {
    final data = (e.widget as Text).data;
    if (data != null && pattern.hasMatch(data)) return data;
  }
  return null;
}

Future<void> pressContinue(WidgetTester tester, {InFlightCountingApiClient? live}) async {
  await tester.tap(find.text('Continue'));
  await settle(tester, live: live);
}

/// Lets dart:io's idle keep-alive timer (15s, created in the test's
/// fake-async zone by a real HTTP call) fire, so flutter_test doesn't fail
/// the test for ending with a pending timer.
Future<void> drainIdleConnectionTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 20));
}
