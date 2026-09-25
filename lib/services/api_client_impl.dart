import 'api_client.dart';
import 'api_dtos.dart';
import 'api_http_client.dart';
import 'app_exception.dart';
import 'auth_token_provider.dart';

/// The real `ApiClient`, built against onboarding-platform's confirmed
/// contract (`app/case/adapters/inbound/{router,schemas}.py`,
/// `app/config/adapters/inbound/{router,schemas}.py`) — see NOTES.md's
/// "Building ApiClientImpl" section for the field-by-field investigation
/// this was built from, including what still doesn't line up end to end.
/// Not wired up by default; `main.dart` keeps `MockApiClient` as the
/// active `ApiClient` unless explicitly switched.
class ApiClientImpl implements ApiClient {
  final ApiHttpClient httpClient;
  final AuthTokenProvider authTokenProvider;

  /// Fired whenever an authenticated call turns out to be unauthorized —
  /// either locally (no token at all) or for real (the server's own
  /// 401). `main.dart` wires this to `AuthNotifier`'s forced-logout path
  /// (see NOTES.md's Phase 1) so the agent is routed back to
  /// `LoginScreen` from wherever they happen to be, rather than every
  /// screen individually having to notice an `UnauthorizedException` and
  /// know what to do about it. A plain callback, not a Riverpod
  /// dependency — `lib/services/` can't import `lib/features/auth/`
  /// (the same boundary rule this class's own doc comment already
  /// explains for why it implements `AuthTokenProvider` directly), so
  /// this is the injection seam instead.
  final void Function()? onUnauthorized;

  ApiClientImpl({required this.httpClient, required this.authTokenProvider, this.onUnauthorized});

  /// Every confirmed endpoint requires `Authorization: Bearer <token>`
  /// (`get_auth_context`). Checked here, before any request goes out —
  /// not left for the server's 401 to report — so "not signed in" is
  /// distinguishable from every other failure mode without relying on a
  /// status code the server also uses for other things. Deliberately
  /// does *not* call [onUnauthorized] itself — [_authenticated] (below)
  /// is the single place that fires it, since this throw happens inside
  /// the closure [_authenticated] wraps and would otherwise fire twice.
  Map<String, String> _authHeaders() {
    final token = authTokenProvider.currentToken();
    if (token == null) {
      throw const UnauthorizedException('Not signed in. Please sign in and try again.');
    }
    return {'Authorization': 'Bearer $token'};
  }

  /// Wraps every authenticated call, [_authHeaders]'s own synchronous
  /// throw included: whether the token is simply missing ([_authHeaders]'s
  /// local check) or the server itself rejects a token that was present
  /// (a genuinely expired or revoked one — 401 from `ApiHttpClient`),
  /// both surface as [UnauthorizedException] and both are caught here,
  /// exactly once. `AuthNotifier`'s own background refresh (see
  /// `token_refresh_policy.dart`) is meant to keep the second case rare in
  /// practice, but a request in flight when a token expires, or a revoked
  /// session, can still hit it — decided, not left ambiguous (NOTES.md's
  /// Phase 1): this app does not attempt an automatic refresh-and-retry of
  /// the original request here; it routes back to login instead, the same
  /// reasoning [UnauthorizedException] was originally split from
  /// [ClientException] for.
  Future<T> _authenticated<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on UnauthorizedException {
      onUnauthorized?.call();
      rethrow;
    }
  }

  @override
  Future<StacFlowManifestDto> fetchFlowManifestStac({
    required String flowId,
    required String clientId,
    String? caseId,
  }) async {
    final response = await _authenticated(() => httpClient.request(
          method: 'POST',
          path: '/cases/flow-manifest/stac',
          headers: _authHeaders(),
          body: {
            'client_id': clientId,
            'workflow_id': flowId,
            'case_id': caseId,
          },
        ));
    return StacFlowManifestDto(
      caseId: response['case_id'] as String,
      workflowVersion: (response['workflow_version'] as List).cast<String>(),
      stages: (response['stages'] as List).cast<Map<String, dynamic>>(),
    );
  }

  @override
  Future<List<FieldOptionDto>> fetchOptions({
    required String clientId,
    required String workflowId,
    required String fieldKey,
    required Map<String, String> dependencyValues,
  }) async {
    // Confirmed, not assumed, per NOTES.md's Phase 3 investigation
    // (superseding the earlier UnimplementedError this method used to
    // throw): FetchFieldOptionsUseCase/the new
    // GET /config/clients/{client_id}/workflows/{workflow_id}/fields/
    // {field_key}/options route (app/config/adapters/inbound/router.py)
    // is exactly the client-side live-resolution path
    // InProcessDynamicOptionsAdapter's own doc comment anticipated but
    // that the backend hadn't yet exposed over HTTP. Read directly, not
    // paraphrased: response_model=list[FieldOptionResponse], auth via
    // require_client_access (same model as .../resolved), dependency
    // values as plain query params (dict(request.query_params) on the
    // backend, matching [dependencyValues] here 1:1 by name).
    final response = await _authenticated(() => httpClient.requestList(
          method: 'GET',
          path: '/config/clients/$clientId/workflows/$workflowId/fields/$fieldKey/options',
          queryParams: dependencyValues,
          headers: _authHeaders(),
        ));
    return response
        .cast<Map<String, dynamic>>()
        .map((json) => FieldOptionDto(label: json['label'] as String, value: json['value'] as String))
        .toList();
  }

  @override
  Future<SubmitCaseResultDto> submitCase({
    required String? caseId,
    required Map<String, dynamic> values,
  }) async {
    if (caseId == null) {
      // A precondition violation, not a network outcome — nothing
      // upstream of ApiClient tracks a case_id yet (see NOTES.md), so
      // this is a caller-contract gap in this app's own current wiring,
      // not something a screen should catch and show a retry button for.
      // Not an AppException for that reason: it isn't a category of
      // failure a real backend could ever produce.
      throw StateError(
        'ApiClientImpl.submitCase requires a non-null caseId (the real backend needs one in the '
        'URL path) — nothing upstream currently provides one; see NOTES.md.',
      );
    }
    final response = await _authenticated(() => httpClient.request(
          method: 'POST',
          path: '/cases/$caseId/submit',
          headers: _authHeaders(),
          body: {
            'values': _nestByStage(values),
            // Confirmed accepted (media_refs, alias mediaRefs) but never
            // persisted server-side regardless (see NOTES.md's Phase 2 —
            // real file upload is a separate endpoint, uploadDocument
            // below, using this response's own recordId).
            'mediaRefs': const <String, String>{},
          },
        ));
    return SubmitCaseResultDto(
      caseId: response['case_id'] as String,
      status: response['status'] as String,
      recordId: response['record_id'] as String?,
      businessRecordId: response['business_record_id'] as String?,
    );
  }

  /// `allValues` (flow's domain — `FlowCaseState.allValues`) flattens
  /// collected values into a single map keyed `'stageId.fieldKey'`. The
  /// confirmed `SubmitCaseRequest.values` wants
  /// `Map<stageId, Map<fieldKey, value>>` instead — a real drift found
  /// while wiring this up (see NOTES.md), fixed here rather than in flow's
  /// domain, since translating this app's internal shape into the wire
  /// shape is exactly what this class is for.
  Map<String, Map<String, dynamic>> _nestByStage(Map<String, dynamic> flatValues) {
    final nested = <String, Map<String, dynamic>>{};
    for (final entry in flatValues.entries) {
      final dot = entry.key.indexOf('.');
      if (dot == -1) continue;
      final stageId = entry.key.substring(0, dot);
      final fieldKey = entry.key.substring(dot + 1);
      (nested[stageId] ??= {})[fieldKey] = entry.value;
    }
    return nested;
  }

  @override
  Future<UploadedDocumentDto> uploadDocument({
    required String recordId,
    required String kind,
    required String filePath,
  }) async {
    final response = await _authenticated(() => httpClient.requestMultipart(
          method: 'POST',
          path: '/identity/records/$recordId/documents/$kind',
          fileFieldName: 'file',
          filePath: filePath,
          headers: _authHeaders(),
        ));
    return UploadedDocumentDto(
      id: response['id'] as String,
      kind: response['kind'] as String,
      fileReference: response['file_reference'] as String,
    );
  }

  LivenessStatusDto _statusFrom(Map<String, dynamic> json) {
    final override = json['override'] as Map<String, dynamic>?;
    return LivenessStatusDto(
      caseStatus: json['case_status'] as String,
      attemptsUsed: json['attempts_used'] as int,
      attemptsCompleted: json['attempts_completed'] as int,
      maxAttempts: json['max_attempts'] as int,
      attemptsRemaining: json['attempts_remaining'] as int,
      attestedPassRecorded: json['attested_pass_recorded'] as bool,
      openAttemptId: json['open_attempt_id'] as String?,
      override: override == null
          ? null
          : LivenessOverrideDto(method: override['method'] as String, decision: override['decision'] as String),
    );
  }

  @override
  Future<LivenessStatusDto> fetchLivenessStatus(String caseId) async {
    final response = await _authenticated(() => httpClient.request(
          method: 'GET',
          path: '/cases/$caseId/liveness-status',
          headers: _authHeaders(),
        ));
    return _statusFrom(response);
  }

  @override
  Future<LivenessAttemptDto> beginLivenessAttempt(String caseId) async {
    final response = await _authenticated(() => httpClient.request(
          method: 'POST',
          path: '/cases/$caseId/liveness-attempts',
          headers: _authHeaders(),
        ));
    return LivenessAttemptDto(
      attemptId: response['attempt_id'] as String,
      attemptNumber: response['attempt_number'] as int,
      status: _statusFrom(response),
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
    final response = await _authenticated(() => httpClient.request(
          method: 'POST',
          path: '/cases/$caseId/liveness-attempts/$attemptId/outcome',
          headers: _authHeaders(),
          body: {
            'attested_liveness_verdict': attestedLivenessVerdict,
            'attested_anti_spoofing_flags': attestedAntiSpoofingFlags,
            if (attestedSessionId != null) 'attested_session_id': attestedSessionId,
          },
        ));
    return _statusFrom(response);
  }

  @override
  Future<AttestedLivenessResultDto> submitAttestedLiveness({
    required String recordId,
    required bool attestedLivenessVerdict,
    required Map<String, dynamic> attestedAntiSpoofingFlags,
    String? attestedSessionId,
    String? attestedDetector,
  }) async {
    final response = await _authenticated(() => httpClient.request(
          method: 'POST',
          path: '/identity/records/$recordId/verifications/device_liveness',
          headers: _authHeaders(),
          body: {
            // The backend's generic field, not a claim: the payload below is.
            'field_checked': 'liveness',
            'payload': {
              'attested_liveness_verdict': attestedLivenessVerdict,
              'attested_anti_spoofing_flags': attestedAntiSpoofingFlags,
              if (attestedSessionId != null) 'attested_session_id': attestedSessionId,
              if (attestedDetector != null) 'attested_detector': attestedDetector,
            },
          },
        ));
    final result = response['result'] as String?;
    if (result == null || !result.startsWith('attested_')) {
      // Anything else means a different provider answered (e.g. the mock
      // "liveness" one): never let that be read as an attested claim.
      throw const ParseException();
    }
    return AttestedLivenessResultDto(
      id: response['id'] as String,
      result: result,
      provider: response['provider'] as String,
    );
  }

  @override
  Future<UploadedDocumentDto> uploadBusinessDocument({
    required String businessRecordId,
    required String kind,
    required String filePath,
  }) async {
    final response = await _authenticated(() => httpClient.requestMultipart(
          method: 'POST',
          path: '/identity/business-records/$businessRecordId/documents/$kind',
          fileFieldName: 'file',
          filePath: filePath,
          headers: _authHeaders(),
        ));
    return UploadedDocumentDto(
      id: response['id'] as String,
      kind: response['kind'] as String,
      fileReference: response['file_reference'] as String,
    );
  }

  @override
  Future<List<ClientSummaryDto>> fetchClients() async {
    final response = await _authenticated(() => httpClient.requestList(
          method: 'GET',
          path: '/clients',
          headers: _authHeaders(),
        ));
    return response
        .cast<Map<String, dynamic>>()
        .map((json) => ClientSummaryDto(id: json['id'] as String, name: json['name'] as String))
        .toList();
  }

  @override
  Future<List<WorkflowSummaryDto>> fetchWorkflows(String clientId) async {
    final response = await _authenticated(() => httpClient.requestList(
          method: 'GET',
          path: '/clients/$clientId/workflows',
          headers: _authHeaders(),
        ));
    return response
        .cast<Map<String, dynamic>>()
        .map((json) => WorkflowSummaryDto(id: json['id'] as String, name: json['name'] as String))
        .toList();
  }
}
