import 'dart:async';
import 'dart:math';

import 'api_dtos.dart';
import 'mock_stac_flow.dart';
import 'app_exception.dart';

/// Injectable network boundary. `MockApiClient` (below) is this app's default
/// implementation; `ApiClientImpl` (api_client_impl.dart) is the real one, built
/// against the backend's confirmed contract (NOTES.md, "Building ApiClientImpl").
///
/// Returns its own DTOs ([StacFlowManifestDto], [FieldOptionDto],
/// [ClientSummaryDto], [WorkflowSummaryDto]), never a feature's domain
/// types: see api_dtos.dart's doc comment for why.
abstract class ApiClient {
  /// [flowId] is kneth's own vocabulary for what the real backend calls `workflow_id` (a real UUID
  /// there, a slug like `'kyc_kyb_collection'` in `MockApiClient`'s demo data); see NOTES.md for why
  /// that naming mismatch was not renamed throughout the app. [caseId] is null to start a brand-new
  /// case, or a previously returned `caseId` to resume one; the backend branches its own
  /// new-vs-resume behavior on whether it is present, so the app only sends what it has.
  ///
  /// Fetches the case's manifest: `POST /cases/flow-manifest/stac`. With no [caseId] the backend
  /// creates a case and returns its real `case_id`; with one it returns that case's frozen stages
  /// (resume). Goes through `ApiHttpClient`'s retry/backoff, bearer-token header and
  /// `onUnauthorized` wrapping rather than `Stac.fromNetwork`, which uses its own Dio and has none
  /// of that (STAC_MIGRATION_SCOPING.md section 12). This is the only manifest route the app uses;
  /// the legacy `POST /cases/flow-manifest` has no mobile consumer left (section 15).
  Future<StacFlowManifestDto> fetchFlowManifestStac({
    required String flowId,
    required String clientId,
    String? caseId,
  });

  /// Live-resolves a DYNAMIC field's options once the agent has supplied
  /// its dependency value(s) — confirmed against
  /// `GET /config/clients/{client_id}/workflows/{workflow_id}/fields/
  /// {field_key}/options?<dependency_name>=<value>` (NOTES.md's Phase 3).
  /// [fieldKey] identifies the field within [clientId]/[workflowId]'s
  /// resolved config; [dependencyValues] are that field's own
  /// `dependsOn` names mapped to their current values (see
  /// `resolveDependencyValues` in flow's domain/, which the caller runs
  /// before ever calling this — readiness and value resolution both
  /// happen there, not here).
  Future<List<FieldOptionDto>> fetchOptions({
    required String clientId,
    required String workflowId,
    required String fieldKey,
    required Map<String, String> dependencyValues,
  });

  /// Submits the entire collected case's field values in a single
  /// request. The mobile app has no notion of which fields are global vs.
  /// tenant-specific; that split is entirely a server-side concern
  /// applied to this flat payload.
  ///
  /// [caseId] is required to be explicitly passed (never defaulted) —
  /// the real backend's `POST /cases/{case_id}/submit` structurally needs
  /// one in its URL path. It's nullable because nothing upstream of
  /// `ApiClient` tracks a case_id yet (see NOTES.md) — `MockApiClient`
  /// tolerates null; `ApiClientImpl` cannot proceed without one and says
  /// so locally rather than attempting a malformed request.
  ///
  /// No longer takes media file paths (see NOTES.md's Phase 2) — the
  /// confirmed contract's own `mediaRefs` field is accepted but never
  /// persisted, and a real, confirmed, separate upload endpoint exists
  /// now ([uploadDocument]), which is what captured files actually go to,
  /// using the [SubmitCaseResultDto.recordId] this call returns.
  Future<SubmitCaseResultDto> submitCase({
    required String? caseId,
    required Map<String, dynamic> values,
  });

  /// Uploads one captured file against [recordId] (from a prior
  /// [submitCase] call) as document [kind] — confirmed against
  /// `POST /identity/records/{record_id}/documents/{kind}`
  /// (`multipart/form-data`). See NOTES.md's Phase 2 for how a captured
  /// stage's id maps onto a confirmed `DocumentKind` value, and why that
  /// mapping is sync's own concern, not this interface's.
  Future<UploadedDocumentDto> uploadDocument({
    required String recordId,
    required String kind,
    required String filePath,
  });

  /// Records the device's own liveness verdict against [recordId] (from a prior
  /// [submitCase] call) — confirmed against
  /// `POST /identity/records/{record_id}/verifications/device_liveness`. The
  /// backend does not verify anything here: it stores the claim as
  /// `attested_passed`/`attested_failed`, so every parameter is named as a
  /// claim. Implementations must throw [ParseException] if the response is not
  /// an `attested_*` result (which would mean the wrong provider answered).
  Future<AttestedLivenessResultDto> submitAttestedLiveness({
    required String recordId,
    required bool attestedLivenessVerdict,
    required Map<String, dynamic> attestedAntiSpoofingFlags,
    String? attestedSessionId,
    String? attestedDetector,
  });

  /// The backend's liveness attempt count for [caseId] (`GET /cases/{id}/liveness-status`).
  Future<LivenessStatusDto> fetchLivenessStatus(String caseId);

  /// Starts the next liveness attempt for [caseId], counted by the backend at once
  /// (`POST /cases/{id}/liveness-attempts`), or returns the still-open one. Throws
  /// [ClientException] 409 once every attempt is used (the case is then awaiting
  /// manual review), whatever the device believes locally.
  Future<LivenessAttemptDto> beginLivenessAttempt(String caseId);

  /// Records the device's own verdict for [attemptId] as an attested claim
  /// (`POST /cases/{id}/liveness-attempts/{attempt}/outcome`) and returns the new
  /// status; the last allowed attempt failing moves the case to review.
  Future<LivenessStatusDto> recordLivenessAttemptOutcome({
    required String caseId,
    required String attemptId,
    required bool attestedLivenessVerdict,
    required Map<String, dynamic> attestedAntiSpoofingFlags,
    String? attestedSessionId,
  });

  /// Business counterpart of [uploadDocument]: uploads one captured file
  /// against [businessRecordId] (from a prior [submitCase] call's
  /// [SubmitCaseResultDto.businessRecordId]) as business document [kind] —
  /// confirmed against `POST /identity/business-records/{business_record_id}/documents/{kind}`
  /// (`multipart/form-data`, no `uploaded_by`: derived from auth
  /// server-side). The backend rejects an individual-only kind here, and a
  /// business-only kind on [uploadDocument].
  Future<UploadedDocumentDto> uploadBusinessDocument({
    required String businessRecordId,
    required String kind,
    required String filePath,
  });

  /// The clients the current agent may act for — confirmed against
  /// `GET /clients`. No UI calls this yet; see NOTES.md.
  Future<List<ClientSummaryDto>> fetchClients();

  /// The workflows configured for [clientId] — confirmed against
  /// `GET /clients/{client_id}/workflows`. No UI calls this yet.
  Future<List<WorkflowSummaryDto>> fetchWorkflows(String clientId);
}

/// Mock implementation returning canned data after a short delay, so the
/// app is fully demoable offline. Swap for an HTTP-backed implementation
/// once a real backend exists.
///
/// Doesn't route through [ApiHttpClient] — there's no real transport here
/// to retry against, and doing so would mean either waiting through real
/// backoff delays in every test or injecting a fake clock into two
/// independent places for no benefit. What it *does* share with a real,
/// eventual `ApiHttpClient`-backed implementation is the exact same
/// [AppException] vocabulary: every simulated failure below throws one of
/// the same variants real HTTP failures would map onto, so anything that
/// handles errors today (a repository, a status type, a screen) is
/// already exercised against real failure shapes, not a fictional one
/// that disappears once real networking lands.
class MockApiClient implements ApiClient {
  MockApiClient({this.enableDemoFailures = false, Random? demoRandom}) : _demoRandom = demoRandom ?? Random();

  /// Set by a test to make the *next* `ApiClient` call throw this instead
  /// of doing its normal work — cleared the moment it fires, so it only
  /// ever affects one call. This is the only failure-injection path a
  /// test should ever rely on; [enableDemoFailures] is for manual/demo
  /// use and is intentionally non-deterministic, so nothing in a test
  /// should assert against it.
  AppException? injectedFailure;

  /// Whether a small, random chance of a simulated transient failure
  /// (a timeout, a 500) is active — for manually driving the app's error
  /// UI without a real backend. Off by default, so existing behavior
  /// (and every existing test) is unaffected unless a caller opts in.
  final bool enableDemoFailures;
  final Random _demoRandom;

  void _maybeFail() {
    final injected = injectedFailure;
    if (injected != null) {
      injectedFailure = null;
      throw injected;
    }
    if (!enableDemoFailures) return;
    if (_demoRandom.nextDouble() > 0.05) return; // ~5% of calls
    const demoFailures = [AppTimeoutException(), ServerException(500)];
    throw demoFailures[_demoRandom.nextInt(demoFailures.length)];
  }

  /// Keyed by [_optionsCacheKey]`(fieldKey, dependencyValues)`. The dependency
  /// value is the parent option's real *value* (`region` = `addis_ababa`, the
  /// same thing the real backend requires, a UUID there): the Stac dropdown
  /// stores an option's value, not its label. (Before the previous renderer was
  /// removed these were keyed by label, because it could only store labels.) Each region's list is deliberately different so a test, or a
  /// person using the app, can tell "district repopulated for the new region"
  /// apart from "district still shows the old region's list."
  static final Map<String, List<FieldOptionDto>> _sampleOptions = {
    _optionsCacheKey('district', {'region': 'addis_ababa'}): [
      const FieldOptionDto(label: 'Bole', value: 'bole'),
      const FieldOptionDto(label: 'Yeka', value: 'yeka'),
      const FieldOptionDto(label: 'Kirkos', value: 'kirkos'),
    ],
    _optionsCacheKey('district', {'region': 'oromia'}): [
      const FieldOptionDto(label: 'Adama', value: 'adama'),
      const FieldOptionDto(label: 'Jimma', value: 'jimma'),
    ],
    _optionsCacheKey('district', {'region': 'amhara'}): [
      const FieldOptionDto(label: 'Bahir Dar', value: 'bahir_dar'),
      const FieldOptionDto(label: 'Gondar', value: 'gondar'),
    ],
    _optionsCacheKey('district', {'region': 'tigray'}): [
      const FieldOptionDto(label: 'Mekelle', value: 'mekelle'),
    ],
    _optionsCacheKey('district', {'region': 'sidama'}): [
      const FieldOptionDto(label: 'Hawassa', value: 'hawassa'),
    ],
    _optionsCacheKey('district', {'region': 'somali'}): [
      const FieldOptionDto(label: 'Jijiga', value: 'jijiga'),
    ],
  };

  static String _optionsCacheKey(String fieldKey, Map<String, String> dependencyValues) {
    final sortedKeys = dependencyValues.keys.toList()..sort();
    final query = sortedKeys.map((k) => '$k=${Uri.encodeComponent(dependencyValues[k]!)}').join('&');
    return '$fieldKey?$query';
  }

  @override
  Future<StacFlowManifestDto> fetchFlowManifestStac({
    required String flowId,
    required String clientId,
    String? caseId,
  }) async {
    _maybeFail();
    await Future.delayed(const Duration(milliseconds: 500));
    // The demo flow's definition lives in tool/mock_flow_descriptors.json; mock_stac_flow.dart is
    // generated from it by the backend's real serializer (tool/gen_mock_stac_flow.py), so the demo
    // shows exactly what the real backend would emit. Every other stage/field of the demo flow
    // (fayda_number, personal_info, ...) is defined there, and nowhere in the app's own code.
    return StacFlowManifestDto(
      caseId: caseId ?? 'mock-case-${DateTime.now().millisecondsSinceEpoch}',
      workflowVersion: const ['1'],
      stages: kMockStacStages,
    );
  }

  @override
  Future<List<FieldOptionDto>> fetchOptions({
    required String clientId,
    required String workflowId,
    required String fieldKey,
    required Map<String, String> dependencyValues,
  }) async {
    _maybeFail();
    await Future.delayed(const Duration(milliseconds: 700));
    return _sampleOptions[_optionsCacheKey(fieldKey, dependencyValues)] ?? const [];
  }

  @override
  Future<SubmitCaseResultDto> submitCase({
    required String? caseId,
    required Map<String, dynamic> values,
  }) async {
    _maybeFail();
    // Unlike ApiClientImpl, a mock has nothing that actually needs a
    // case_id (there's no URL to put it in), so a null one is tolerated
    // rather than rejected — see the interface doc comment. A fake
    // recordId is always returned (not conditionally, unlike the real
    // backend's "only if GLOBAL fields were submitted" rule) so every
    // demo/manual run can exercise the document-upload step regardless of
    // which stages happen to be in the canned flow.
    await Future.delayed(const Duration(milliseconds: 900));
    return SubmitCaseResultDto(
      caseId: caseId ?? 'mock-case-id',
      status: 'pending',
      recordId: 'mock-record-id',
      businessRecordId: 'mock-business-record-id',
    );
  }

  @override
  Future<UploadedDocumentDto> uploadDocument({
    required String recordId,
    required String kind,
    required String filePath,
  }) async {
    _maybeFail();
    await Future.delayed(const Duration(milliseconds: 600));
    return UploadedDocumentDto(id: 'mock-document-id', kind: kind, fileReference: 'mock://$recordId/$kind');
  }

  @override
  Future<UploadedDocumentDto> uploadBusinessDocument({
    required String businessRecordId,
    required String kind,
    required String filePath,
  }) async {
    _maybeFail();
    await Future.delayed(const Duration(milliseconds: 600));
    return UploadedDocumentDto(id: 'mock-document-id', kind: kind, fileReference: 'mock://$businessRecordId/$kind');
  }

  @override
  Future<AttestedLivenessResultDto> submitAttestedLiveness({
    required String recordId,
    required bool attestedLivenessVerdict,
    required Map<String, dynamic> attestedAntiSpoofingFlags,
    String? attestedSessionId,
    String? attestedDetector,
  }) async {
    _maybeFail();
    await Future.delayed(const Duration(milliseconds: 400));
    return AttestedLivenessResultDto(
      id: 'mock-attestation-id',
      result: attestedLivenessVerdict ? 'attested_passed' : 'attested_failed',
      provider: 'mock-device-attested-liveness',
    );
  }

  // A tiny in-memory stand-in for the backend's per-case liveness count, so the
  // offline demo exercises the same flow (3 attempts, then review). The real
  // counting, rejection and override are the backend's; this proves nothing about them.
  final Map<String, List<bool?>> _mockLivenessAttempts = {};

  LivenessStatusDto _mockLivenessStatus(String caseId) {
    final attempts = _mockLivenessAttempts[caseId] ?? const <bool?>[];
    const max = 3;
    final passed = attempts.contains(true);
    final exhausted = attempts.length >= max && !attempts.contains(null) && !passed;
    return LivenessStatusDto(
      caseStatus: exhausted ? 'needs_manual_review' : 'in_progress',
      attemptsUsed: attempts.length,
      attemptsCompleted: attempts.where((a) => a != null).length,
      maxAttempts: max,
      attemptsRemaining: (max - attempts.length).clamp(0, max),
      attestedPassRecorded: passed,
      openAttemptId: attempts.contains(null) ? '$caseId#${attempts.length}' : null,
    );
  }

  @override
  Future<LivenessStatusDto> fetchLivenessStatus(String caseId) async {
    _maybeFail();
    return _mockLivenessStatus(caseId);
  }

  @override
  Future<LivenessAttemptDto> beginLivenessAttempt(String caseId) async {
    _maybeFail();
    final attempts = _mockLivenessAttempts.putIfAbsent(caseId, () => []);
    if (!attempts.contains(null)) {
      if (attempts.length >= 3 || attempts.contains(true)) {
        throw const ClientException(409, 'The liveness check has used all 3 attempts for this case.');
      }
      attempts.add(null);
    }
    return LivenessAttemptDto(
      attemptId: '$caseId#${attempts.length}',
      attemptNumber: attempts.length,
      status: _mockLivenessStatus(caseId),
    );
  }

  @override
  Future<LivenessStatusDto> recordLivenessAttemptOutcome({
    required String caseId,
    required String attemptId,
    required bool attestedLivenessVerdict,
    required Map<String, dynamic> attestedAntiSpoofingFlags,
    String? attestedSessionId,
  }) async {
    _maybeFail();
    final attempts = _mockLivenessAttempts[caseId];
    final open = attempts?.indexOf(null) ?? -1;
    if (attempts == null || open < 0) throw const ClientException(409, 'No open liveness attempt.');
    attempts[open] = attestedLivenessVerdict;
    return _mockLivenessStatus(caseId);
  }

  /// A couple of canned entries — enough to exercise callers that list
  /// clients/workflows without pretending to model a real client roster.
  static final List<ClientSummaryDto> _clients = [
    const ClientSummaryDto(id: 'client-1', name: 'Awash Bank'),
    const ClientSummaryDto(id: 'client-2', name: 'Dashen Bank'),
  ];

  static final Map<String, List<WorkflowSummaryDto>> _workflows = {
    'client-1': [const WorkflowSummaryDto(id: 'kyc_kyb_collection', name: 'KYC/KYB collection')],
    'client-2': [const WorkflowSummaryDto(id: 'kyc_kyb_collection', name: 'KYC/KYB collection')],
  };

  @override
  Future<List<ClientSummaryDto>> fetchClients() async {
    _maybeFail();
    await Future.delayed(const Duration(milliseconds: 400));
    return _clients;
  }

  @override
  Future<List<WorkflowSummaryDto>> fetchWorkflows(String clientId) async {
    _maybeFail();
    await Future.delayed(const Duration(milliseconds: 400));
    return _workflows[clientId] ?? const [];
  }
}
