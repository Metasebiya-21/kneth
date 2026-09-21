import 'dart:async';
import 'dart:math';

import 'api_dtos.dart';
import 'app_exception.dart';

/// Injectable network boundary. `MockApiClient` (below) is this app's only
/// wired-up implementation; `ApiClientImpl` (api_client_impl.dart) is a
/// second, selectable one built against the real backend's confirmed
/// contract — see NOTES.md's "Building ApiClientImpl" section.
///
/// Returns its own DTOs ([FlowManifestDto], [FieldOptionDto],
/// [ClientSummaryDto], [WorkflowSummaryDto]), never a feature's domain
/// types — see api_dtos.dart's doc comment for why, and NOTES.md for the
/// leak this fixed.
abstract class ApiClient {
  /// Fetches the fully-resolved manifest for [flowId] (kneth's own
  /// vocabulary for what the real backend calls `workflow_id` — a real
  /// UUID there, a slug like `'kyc_kyb_collection'` in `MockApiClient`'s
  /// canned data; see NOTES.md for why this naming mismatch wasn't
  /// renamed throughout the app as part of this) as configured for
  /// [clientId]. [caseId] is null to start a brand-new case, or a
  /// previously-returned [FlowManifestDto.caseId] to resume one — the real
  /// backend branches its own new-vs-resume behavior off whether this is
  /// present; this app doesn't need to replicate that logic, only send
  /// what it has.
  Future<FlowManifestDto> fetchFlowManifest({
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

  /// Stands in for a real backend's flow-definition store: for each flowId,
  /// an ordered list of stage descriptors, already merged for whichever
  /// client is passed to [fetchFlowManifest]. This is the ONLY place the
  /// kyc_kyb_collection flow's stages/fields are defined — main.dart and
  /// every screen are generic and know nothing about fayda_number,
  /// personal_info, etc.
  static final Map<String, List<Map<String, dynamic>>> _flows = {
    'kyc_kyb_collection': [
      {
        'stageId': 'fayda_verification',
        'title': 'Fayda verification',
        'screenType': 'GENERIC_FORM',
        'fields': [
          {
            'key': 'fayda_number',
            'label': 'Fayda number',
            'type': 'TEXT',
            'inputMode': 'FREE',
            'property': {
              'order': 1,
              'isRequired': true,
              'isHidden': false,
              'regex': r'^\d{16}$',
            },
          },
          {
            'key': 'region',
            'label': 'Region',
            'type': 'SELECT',
            'inputMode': 'ENUM',
            'property': {
              'order': 2,
              'isRequired': true,
              'isHidden': false,
              'options': [
                {'label': 'Addis Ababa', 'value': 'addis_ababa'},
                {'label': 'Oromia', 'value': 'oromia'},
                {'label': 'Amhara', 'value': 'amhara'},
                {'label': 'Tigray', 'value': 'tigray'},
                {'label': 'Sidama', 'value': 'sidama'},
                {'label': 'Somali', 'value': 'somali'},
              ],
            },
          },
          // A genuine cascading DYNAMIC example: district's own options
          // depend on which region was picked above, fetched fresh every
          // time region changes (see DynamicOptionsController) — district
          // starts unavailable until region has a value.
          {
            'key': 'district',
            'label': 'District',
            'type': 'SELECT',
            'inputMode': 'DYNAMIC',
            'property': {
              'order': 3,
              'isRequired': true,
              'isHidden': false,
              'dependsOn': ['region'],
              'dynamicConfig': {
                'endpoint': '/options/regions/{region}/districts',
                'method': 'GET',
              },
            },
          },
        ],
      },
      {
        'stageId': 'identification_card',
        'title': 'Identification card',
        'screenType': 'NATIVE_CAPTURE',
        'nativeHandler': 'photo_capture',
        'fields': [],
      },
      {
        'stageId': 'personal_info',
        'title': 'Personal information',
        'screenType': 'GENERIC_FORM',
        'fields': [
          {
            'key': 'full_name',
            'label': 'Full Name',
            'type': 'TEXT',
            'inputMode': 'FREE',
            // Example of a backend-attached consent requirement — field-
            // level per the confirmed contract (ManifestFieldResponse),
            // not stage-level (see NOTES.md's Phase 5). Not acted on by
            // any screen yet; here purely as a shape check.
            'consentRequired': true,
            'property': {
              'order': 1,
              'isRequired': true,
              'isHidden': false,
              'minLen': 3,
              'maxLen': 64,
              'regex': r'^[a-zA-Z\s/]{1,64}$',
            },
          },
          {
            'key': 'mother_name',
            'label': 'Mother Name',
            'type': 'TEXT',
            'inputMode': 'FREE',
            'property': {
              'order': 2,
              'isRequired': true,
              'isHidden': false,
              'minLen': 3,
              'maxLen': 64,
              'regex': r'^[a-zA-Z\s/]{1,64}$',
            },
          },
          {
            'key': 'language_preference',
            'label': 'Language Preference',
            'type': 'SELECT',
            'inputMode': 'ENUM',
            // Example of a backend-attached prefill: last-known language
            // preference for this client, carried over so the agent
            // doesn't have to re-ask. Field-level, a plain string — see
            // NOTES.md's Phase 5 (this used to be a stage-level Map).
            'prefill': 'amharic',
            'property': {
              'order': 3,
              'isRequired': true,
              'isHidden': false,
              'options': [
                {'label': 'Amharic', 'value': 'amharic'},
                {'label': 'English', 'value': 'english'},
                {'label': 'Afan Oromifa', 'value': 'afan_oromo'},
                {'label': 'Tigrigna', 'value': 'tigrigna'},
              ],
            },
          },
        ],
      },
      {
        'stageId': 'consent_signature',
        'title': 'Consent signature',
        'screenType': 'NATIVE_CAPTURE',
        'nativeHandler': 'signature_capture',
        'fields': [],
      },
      {
        'stageId': 'association_details',
        'title': 'Association details',
        'screenType': 'GENERIC_FORM',
        'fields': [
          {
            'key': 'association_type',
            'label': 'Association type',
            'type': 'SELECT',
            'inputMode': 'ENUM',
            'property': {
              'order': 1,
              'isRequired': true,
              'isHidden': false,
              'options': [
                {'label': 'Individual', 'value': 'Individual'},
                {'label': 'Group', 'value': 'Group'},
              ],
            },
          },
          {
            'key': 'company_name',
            'label': 'Company name',
            'type': 'TEXT',
            'inputMode': 'FREE',
            'property': {
              'order': 2,
              // Base values: hidden/not required by default — only
              // relevant once association_type == "Group".
              'isRequired': false,
              'isHidden': true,
              'dependsOn': ['association_type'],
              'conditionalDependency': {
                'if': [
                  {'field': 'association_type', 'op': 'eq', 'value': 'Group'},
                ],
                'then': {'isRequired': true, 'isHidden': false},
                'else': {'isRequired': false, 'isHidden': true},
              },
            },
          },
        ],
      },
    ],
  };

  /// Keyed by [_optionsCacheKey]`(fieldKey, dependencyValues)` — no longer
  /// a resolved URL (see [fetchOptions]'s own doc comment for why that
  /// changed). Important, easy to get wrong: kifiya_rendering_engine's
  /// dropdowns only ever store/submit an option's *label* — there's no
  /// separate value round-tripped back from the plugin (see
  /// rendering_engine_adapter.dart's doc comment; `FieldOptionDto.value`
  /// itself is never read anywhere in this render pipeline, only
  /// `.label`). That means `region`'s stored form value is the literal
  /// string "Addis Ababa", not a slug like "addis_ababa" — so the keys
  /// below have to match that exact string, not some cleaner
  /// machine-readable id. Each region's list is deliberately different so
  /// a test (or a person using the app) can tell "district repopulated
  /// for the new region" apart from "district still shows the old
  /// region's list."
  static final Map<String, List<FieldOptionDto>> _sampleOptions = {
    _optionsCacheKey('district', {'region': 'Addis Ababa'}): [
      const FieldOptionDto(label: 'Bole', value: 'bole'),
      const FieldOptionDto(label: 'Yeka', value: 'yeka'),
      const FieldOptionDto(label: 'Kirkos', value: 'kirkos'),
    ],
    _optionsCacheKey('district', {'region': 'Oromia'}): [
      const FieldOptionDto(label: 'Adama', value: 'adama'),
      const FieldOptionDto(label: 'Jimma', value: 'jimma'),
    ],
    _optionsCacheKey('district', {'region': 'Amhara'}): [
      const FieldOptionDto(label: 'Bahir Dar', value: 'bahir_dar'),
      const FieldOptionDto(label: 'Gondar', value: 'gondar'),
    ],
    _optionsCacheKey('district', {'region': 'Tigray'}): [
      const FieldOptionDto(label: 'Mekelle', value: 'mekelle'),
    ],
    _optionsCacheKey('district', {'region': 'Sidama'}): [
      const FieldOptionDto(label: 'Hawassa', value: 'hawassa'),
    ],
    _optionsCacheKey('district', {'region': 'Somali'}): [
      const FieldOptionDto(label: 'Jijiga', value: 'jijiga'),
    ],
  };

  static String _optionsCacheKey(String fieldKey, Map<String, String> dependencyValues) {
    final sortedKeys = dependencyValues.keys.toList()..sort();
    final query = sortedKeys.map((k) => '$k=${Uri.encodeComponent(dependencyValues[k]!)}').join('&');
    return '$fieldKey?$query';
  }

  @override
  Future<FlowManifestDto> fetchFlowManifest({
    required String flowId,
    required String clientId,
    String? caseId,
  }) async {
    _maybeFail();
    await Future.delayed(const Duration(milliseconds: 500));
    return FlowManifestDto(
      // A real case_id is server-assigned; caseId here just echoes a
      // resumed one back, or invents a fresh-looking one for a new case —
      // good enough for a mock that nothing downstream reads yet.
      caseId: caseId ?? 'mock-case-${DateTime.now().millisecondsSinceEpoch}',
      workflowVersion: const ['1'],
      stagesJson: _flows[flowId] ?? const [],
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
