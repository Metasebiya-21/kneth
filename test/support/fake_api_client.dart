import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sdui_demo/services/api_client.dart';
import 'package:sdui_demo/services/app_exception.dart';
import 'package:sdui_demo/services/api_dtos.dart';

/// A three-stage fake flow (one form stage, one native-capture stage, one
/// more form stage) with call counters, so tests can assert the
/// single-fetch/single-submit contract instead of just its final state.
class FakeApiClient implements ApiClient {
  FakeApiClient({
    List<Map<String, dynamic>>? stacStages,
    this.optionsByEndpoint = const {},
    this.clients = const [],
    this.workflowsByClientId = const {},
    this.fetchClientsError,
    this.fetchWorkflowsError,
  }) : stacStages = stacStages ?? defaultStacStages;

  int submitCaseCallCount = 0;

  /// Returned by [submitCase] for every call — override via the
  /// constructor when a test needs a specific (or null) recordId.
  String? recordIdToReturn = 'fake-record-id';

  /// Same, for the business record (null = no business fields submitted).
  String? businessRecordIdToReturn;

  Map<String, dynamic>? lastSubmittedValues;

  /// Stac-shaped stages returned by [fetchFlowManifestStac]: the default three-stage flow, or
  /// whatever a test sets (usually a recorded real-backend fixture).
  List<Map<String, dynamic>> stacStages;
  int fetchFlowManifestStacCallCount = 0;

  /// Every case_id each [fetchFlowManifestStac] call was given (null = a new case was requested).
  final List<String?> stacCaseIdsRequested = [];

  /// The case_id issued for a new case (a resumed case's own id is echoed back instead).
  String caseIdToIssue = 'fake-case-id';

  @override
  Future<StacFlowManifestDto> fetchFlowManifestStac({
    required String flowId,
    required String clientId,
    String? caseId,
  }) async {
    fetchFlowManifestStacCallCount++;
    stacCaseIdsRequested.add(caseId);
    return StacFlowManifestDto(
      caseId: caseId ?? caseIdToIssue,
      workflowVersion: const ['1'],
      stages: stacStages,
    );
  }

  /// Canned options keyed by [optionsKey]`(fieldKey, dependencyValues)` — empty by default; tests
  /// that exercise DYNAMIC fields pass their own via the constructor. Keyed by dependency values
  /// too, not just field key, so a test can give different dependency values (e.g. different
  /// regions) different results — mirrors `MockApiClient._optionsCacheKey`.
  final Map<String, List<FieldOptionDto>> optionsByEndpoint;
  int fetchOptionsCallCount = 0;
  final List<String> fetchOptionsFieldKeys = [];
  final List<Map<String, String>> fetchOptionsDependencyValues = [];

  /// When set, [fetchOptions] throws it (once per call, until cleared).
  Object? fetchOptionsError;

  /// When set, [fetchOptions] waits for it before answering — lets a test observe the "loading" state.
  Completer<void>? fetchOptionsGate;

  static String optionsKey(String fieldKey, Map<String, String> dependencyValues) {
    final sortedKeys = dependencyValues.keys.toList()..sort();
    final query = sortedKeys.map((k) => '$k=${dependencyValues[k]}').join('&');
    return '$fieldKey?$query';
  }

  @override
  Future<List<FieldOptionDto>> fetchOptions({
    required String clientId,
    required String workflowId,
    required String fieldKey,
    required Map<String, String> dependencyValues,
  }) async {
    fetchOptionsCallCount++;
    fetchOptionsFieldKeys.add(fieldKey);
    fetchOptionsDependencyValues.add(dependencyValues);
    final gate = fetchOptionsGate;
    if (gate != null) await gate.future;
    final error = fetchOptionsError;
    if (error != null) throw error;
    return optionsByEndpoint[optionsKey(fieldKey, dependencyValues)] ?? const [];
  }

  String? lastSubmittedCaseId;

  @override
  Future<SubmitCaseResultDto> submitCase({
    required String? caseId,
    required Map<String, dynamic> values,
  }) async {
    submitCaseCallCount++;
    lastSubmittedCaseId = caseId;
    lastSubmittedValues = values;
    return SubmitCaseResultDto(caseId: caseId ?? 'fake-case-id', status: 'pending', recordId: recordIdToReturn, businessRecordId: businessRecordIdToReturn);
  }

  int uploadDocumentCallCount = 0;
  final List<Map<String, String>> uploadDocumentCalls = [];
  Object? uploadDocumentError;

  @override
  Future<UploadedDocumentDto> uploadDocument({
    required String recordId,
    required String kind,
    required String filePath,
  }) async {
    uploadDocumentCallCount++;
    uploadDocumentCalls.add({'recordId': recordId, 'kind': kind, 'filePath': filePath});
    final error = uploadDocumentError;
    if (error != null) throw error;
    return UploadedDocumentDto(id: 'fake-document-id', kind: kind, fileReference: 'fake://$recordId/$kind');
  }

  // --- a scripted stand-in for the backend's per-case liveness count -------------------------
  // Mirrors the server's rules closely enough to drive the app's flows (an open attempt is
  // reused, a fourth begin is a 409, the last failure moves the case to review). The real
  // rules are the backend's, verified by its own unit/integration tests and the live tests.
  static const livenessMax = 3;

  /// null = an attempt that was begun but has no outcome yet.
  final List<bool?> livenessAttempts = [];

  /// Forces the case status the fake reports (e.g. 'needs_manual_review', 'rejected').
  String? livenessCaseStatusForced;
  LivenessOverrideDto? livenessOverride;
  Object? beginLivenessError;
  Object? recordLivenessOutcomeError;
  Object? fetchLivenessStatusError;
  int beginLivenessCallCount = 0;
  int recordLivenessOutcomeCallCount = 0;
  int fetchLivenessStatusCallCount = 0;
  final List<Map<String, dynamic>> recordedLivenessOutcomes = [];

  bool get _livenessPassed => livenessAttempts.contains(true);
  bool get _livenessExhausted =>
      livenessAttempts.length >= livenessMax && !livenessAttempts.contains(null) && !_livenessPassed;

  LivenessStatusDto livenessStatusNow() {
    final status = livenessCaseStatusForced ?? (_livenessExhausted ? 'needs_manual_review' : 'in_progress');
    return LivenessStatusDto(
      caseStatus: status,
      attemptsUsed: livenessAttempts.length,
      attemptsCompleted: livenessAttempts.where((a) => a != null).length,
      maxAttempts: livenessMax,
      attemptsRemaining: (livenessMax - livenessAttempts.length).clamp(0, livenessMax),
      attestedPassRecorded: _livenessPassed,
      openAttemptId: livenessAttempts.contains(null) ? 'attempt-${livenessAttempts.length}' : null,
      override: livenessOverride,
    );
  }

  @override
  Future<LivenessStatusDto> fetchLivenessStatus(String caseId) async {
    fetchLivenessStatusCallCount++;
    final error = fetchLivenessStatusError;
    if (error != null) throw error;
    return livenessStatusNow();
  }

  @override
  Future<LivenessAttemptDto> beginLivenessAttempt(String caseId) async {
    beginLivenessCallCount++;
    final error = beginLivenessError;
    if (error != null) throw error;
    if (livenessCaseStatusForced == 'needs_manual_review' || _livenessExhausted) {
      throw const ClientException(409, 'the liveness check has used all 3 attempts for this case');
    }
    if (!livenessAttempts.contains(null)) livenessAttempts.add(null);
    return LivenessAttemptDto(
      attemptId: 'attempt-${livenessAttempts.length}',
      attemptNumber: livenessAttempts.length,
      status: livenessStatusNow(),
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
    recordLivenessOutcomeCallCount++;
    final error = recordLivenessOutcomeError;
    if (error != null) throw error;
    recordedLivenessOutcomes.add({
      'caseId': caseId,
      'attemptId': attemptId,
      'attestedLivenessVerdict': attestedLivenessVerdict,
      'attestedAntiSpoofingFlags': attestedAntiSpoofingFlags,
      'attestedSessionId': attestedSessionId,
    });
    final open = livenessAttempts.indexOf(null);
    if (open >= 0) livenessAttempts[open] = attestedLivenessVerdict;
    return livenessStatusNow();
  }

  int submitAttestedLivenessCallCount = 0;
  final List<Map<String, dynamic>> submitAttestedLivenessCalls = [];
  Object? submitAttestedLivenessError;

  @override
  Future<AttestedLivenessResultDto> submitAttestedLiveness({
    required String recordId,
    required bool attestedLivenessVerdict,
    required Map<String, dynamic> attestedAntiSpoofingFlags,
    String? attestedSessionId,
    String? attestedDetector,
  }) async {
    submitAttestedLivenessCallCount++;
    submitAttestedLivenessCalls.add({
      'recordId': recordId,
      'attestedLivenessVerdict': attestedLivenessVerdict,
      'attestedAntiSpoofingFlags': attestedAntiSpoofingFlags,
      'attestedSessionId': attestedSessionId,
      'attestedDetector': attestedDetector,
    });
    final error = submitAttestedLivenessError;
    if (error != null) throw error;
    return AttestedLivenessResultDto(
      id: 'fake-attestation-id',
      result: attestedLivenessVerdict ? 'attested_passed' : 'attested_failed',
      provider: 'fake-device-attested-liveness',
    );
  }

  int uploadBusinessDocumentCallCount = 0;
  final List<Map<String, String>> uploadBusinessDocumentCalls = [];
  Object? uploadBusinessDocumentError;

  @override
  Future<UploadedDocumentDto> uploadBusinessDocument({
    required String businessRecordId,
    required String kind,
    required String filePath,
  }) async {
    uploadBusinessDocumentCallCount++;
    uploadBusinessDocumentCalls.add({'businessRecordId': businessRecordId, 'kind': kind, 'filePath': filePath});
    final error = uploadBusinessDocumentError;
    if (error != null) throw error;
    return UploadedDocumentDto(id: 'fake-document-id', kind: kind, fileReference: 'fake://$businessRecordId/$kind');
  }

  final List<ClientSummaryDto> clients;
  final Map<String, List<WorkflowSummaryDto>> workflowsByClientId;
  final Object? fetchClientsError;
  final Object? fetchWorkflowsError;
  int fetchClientsCallCount = 0;
  int fetchWorkflowsCallCount = 0;
  String? lastFetchWorkflowsClientId;

  @override
  Future<List<ClientSummaryDto>> fetchClients() async {
    fetchClientsCallCount++;
    final error = fetchClientsError;
    if (error != null) throw error;
    return clients;
  }

  @override
  Future<List<WorkflowSummaryDto>> fetchWorkflows(String clientId) async {
    fetchWorkflowsCallCount++;
    lastFetchWorkflowsClientId = clientId;
    final error = fetchWorkflowsError;
    if (error != null) throw error;
    return workflowsByClientId[clientId] ?? const [];
  }

  /// The default flow: a form stage (required `name`), a photo stage, a form stage (optional
  /// `email`), in Stac shape produced by the backend's real serializer
  /// (tool/gen_ported_stac_fixtures.py -> test/fixtures/stac/ported_fixtures.json).
  static List<Map<String, dynamic>> get defaultStacStages {
    final ported = jsonDecode(File('test/fixtures/stac/ported_fixtures.json').readAsStringSync()) as Map<String, dynamic>;
    return [for (final s in (ported['fake_default_stages'] as List)) (s as Map).cast<String, dynamic>()];
  }
}
