import 'dart:async';

import '../models/field_config.dart';

/// Injectable network boundary. There is no real backend yet — every
/// caller above this interface talks to [ApiClient], never to an HTTP
/// client directly, so a real implementation can be dropped in later
/// without touching UI code.
abstract class ApiClient {
  /// Fetches the next stage of [flowId]'s flow. Pass [afterStageId]: null to
  /// fetch the very first stage; otherwise the stage just completed, along
  /// with the [submittedValues] for it (server can use these to branch).
  /// Returns the next stage's raw JSON descriptor, or null when the flow is
  /// complete — this is what makes the UI fully server-driven: the client
  /// holds no local stage list, just whatever came back last.
  Future<Map<String, dynamic>?> fetchNextStage({
    required String flowId,
    required String? afterStageId,
    required Map<String, dynamic>? submittedValues,
  });

  Future<List<FieldOption>> fetchOptions(String endpoint);

  /// Uploads collected form/native-capture values for a completed case.
  Future<void> uploadCaseData(Map<String, dynamic> values);

  /// Uploads captured media (photos, signatures) by local file path.
  Future<void> uploadMedia(List<String> filePaths);

  /// Server-side finalization step (e.g. document processing/OCR/checks).
  Future<void> finalizeCase();
}

/// Mock implementation returning canned data after a short delay, so the
/// app is fully demoable offline. Swap for an HTTP-backed implementation
/// once a real backend exists.
class MockApiClient implements ApiClient {
  /// Stands in for a real backend's flow-definition store: for each flowId,
  /// an ordered list of stage descriptors. This is the ONLY place the
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
            'inputMode': 'DYNAMIC',
            'property': {
              'order': 2,
              'isRequired': true,
              'isHidden': false,
              'dynamicConfig': {
                'endpoint': '/options/regions',
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

  static final Map<String, List<FieldOption>> _sampleOptions = {
    '/options/regions': [
      FieldOption(label: 'Addis Ababa', value: 'addis_ababa'),
      FieldOption(label: 'Oromia', value: 'oromia'),
      FieldOption(label: 'Amhara', value: 'amhara'),
      FieldOption(label: 'Tigray', value: 'tigray'),
      FieldOption(label: 'Sidama', value: 'sidama'),
      FieldOption(label: 'Somali', value: 'somali'),
    ],
  };

  @override
  Future<Map<String, dynamic>?> fetchNextStage({
    required String flowId,
    required String? afterStageId,
    required Map<String, dynamic>? submittedValues,
  }) async {
    // TODO(real-backend): replace with an HTTP call that returns the next
    // stage's schema — the server can use [submittedValues] to branch.
    await Future.delayed(const Duration(milliseconds: 500));
    final stages = _flows[flowId] ?? const [];
    if (afterStageId == null) {
      return stages.isEmpty ? null : stages.first;
    }
    final index = stages.indexWhere((stage) => stage['stageId'] == afterStageId);
    if (index == -1 || index + 1 >= stages.length) return null;
    return stages[index + 1];
  }

  @override
  Future<List<FieldOption>> fetchOptions(String endpoint) async {
    // TODO(real-backend): replace with an HTTP GET against [endpoint].
    await Future.delayed(const Duration(milliseconds: 700));
    return _sampleOptions[endpoint] ?? const [];
  }

  @override
  Future<void> uploadCaseData(Map<String, dynamic> values) async {
    // TODO(real-backend): replace with an HTTP POST of the case payload.
    await Future.delayed(const Duration(milliseconds: 900));
  }

  @override
  Future<void> uploadMedia(List<String> filePaths) async {
    // TODO(real-backend): replace with a multipart upload per file.
    await Future.delayed(const Duration(milliseconds: 900));
  }

  @override
  Future<void> finalizeCase() async {
    // TODO(real-backend): replace with a call that kicks off/confirms
    // server-side processing (OCR, checks, etc).
    await Future.delayed(const Duration(milliseconds: 700));
  }
}
