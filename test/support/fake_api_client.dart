import 'package:sdui_demo/services/api_client.dart';
import 'package:sdui_demo/services/api_dtos.dart';

/// A three-stage fake flow (one form stage, one native-capture stage, one
/// more form stage) with call counters, so tests can assert the
/// single-fetch/single-submit contract instead of just its final state.
class FakeApiClient implements ApiClient {
  FakeApiClient({
    List<Map<String, dynamic>>? stagesJson,
    this.optionsByEndpoint = const {},
    this.clients = const [],
    this.workflowsByClientId = const {},
    this.fetchClientsError,
    this.fetchWorkflowsError,
  }) : stagesJson = stagesJson ?? defaultStagesJson;

  final List<Map<String, dynamic>> stagesJson;

  int fetchFlowManifestCallCount = 0;
  int submitCaseCallCount = 0;

  /// Returned by [submitCase] for every call — override via the
  /// constructor when a test needs a specific (or null) recordId.
  String? recordIdToReturn = 'fake-record-id';

  Map<String, dynamic>? lastSubmittedValues;

  @override
  Future<FlowManifestDto> fetchFlowManifest({
    required String flowId,
    required String clientId,
    String? caseId,
  }) async {
    fetchFlowManifestCallCount++;
    return FlowManifestDto(
      caseId: caseId ?? 'fake-case-id',
      workflowVersion: const ['1'],
      stagesJson: stagesJson,
    );
  }

  /// Canned options keyed by [optionsKey]`(fieldKey, dependencyValues)` —
  /// empty by default; tests that exercise DYNAMIC fields pass their own
  /// via the constructor. Keyed by dependency values too, not just field
  /// key, so a test can give different dependency values (e.g. different
  /// regions) different results — mirrors `MockApiClient._optionsCacheKey`.
  final Map<String, List<FieldOptionDto>> optionsByEndpoint;
  int fetchOptionsCallCount = 0;
  final List<String> fetchOptionsFieldKeys = [];

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
    return SubmitCaseResultDto(caseId: caseId ?? 'fake-case-id', status: 'pending', recordId: recordIdToReturn);
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

  static const List<Map<String, dynamic>> defaultStagesJson = [
    {
      'stageId': 'stage_a',
      'title': 'Stage A',
      'screenType': 'GENERIC_FORM',
      'fields': <Map<String, dynamic>>[
        {
          'key': 'name',
          'label': 'Name',
          'type': 'TEXT',
          'inputMode': 'FREE',
          'property': {'order': 1, 'isRequired': true, 'isHidden': false},
        },
      ],
    },
    {
      'stageId': 'stage_b',
      'title': 'Stage B',
      'screenType': 'NATIVE_CAPTURE',
      'nativeHandler': 'photo_capture',
      'fields': <Map<String, dynamic>>[],
    },
    {
      'stageId': 'stage_c',
      'title': 'Stage C',
      'screenType': 'GENERIC_FORM',
      'fields': <Map<String, dynamic>>[
        {
          'key': 'email',
          'label': 'Email',
          'type': 'TEXT',
          'inputMode': 'FREE',
          'property': {'order': 1, 'isRequired': false, 'isHidden': false},
        },
      ],
    },
  ];
}
