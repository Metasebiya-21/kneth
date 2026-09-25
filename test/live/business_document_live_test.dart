// LIVE tier: business document upload against the REAL running backend — real Keycloak login,
// real POST /cases/flow-manifest/stac, real POST /cases/{id}/submit returning BOTH record_id and
// business_record_id for a combined KYC+KYB submission, then real multipart uploads: the
// individual document to POST /identity/records/{record_id}/documents/{kind} and the business
// document to POST /identity/business-records/{business_record_id}/documents/{kind}.
//
// Needs the seeds in tool/ including tool/seed_stac_business_docs.sql (the GLOBAL `business_info`
// stage and the `trade_license` capture stage). Skips itself when the backend isn't reachable.
//
//   flutter test test/live/business_document_live_test.dart      (or: make live)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sdui_demo/features/auth/data/keycloak_auth_repository_impl.dart';
import 'package:sdui_demo/features/sync/data/sync_repository_impl.dart';
import 'package:sdui_demo/features/sync/domain/sync_status.dart';
import 'package:sdui_demo/services/api_client_impl.dart';
import 'package:sdui_demo/services/api_http_client.dart';
import 'package:sdui_demo/services/app_exception.dart';

const _backend = 'http://127.0.0.1:8000';
const _keycloak = 'http://127.0.0.1:8080';
const _agentUsername = '826dfc90-f28b-4dde-806e-f15ab51c8e84';
const _agentPassword = 'dev-agent-password-123';
final _uuid = RegExp(r'^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$');

class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _v = {};
  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async => _v[key] = value;
  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => _v[key];
  @override
  Future<void> delete({required String key, required Map<String, String> options}) async => _v.remove(key);
  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async => _v.containsKey(key);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async => _v.clear();
  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => Map.of(_v);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool reachable;
  late ApiClientImpl api;
  late KeycloakAuthRepositoryImpl auth;
  late String clientId;
  late String workflowId;
  late File image;

  // A tiny valid PNG, written once and uploaded as both the individual and the business document.
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  setUpAll(() async {
    HttpOverrides.global = null;
    try {
      reachable = (await http.get(Uri.parse('$_backend/docs')).timeout(const Duration(seconds: 5))).statusCode == 200;
    } catch (_) {
      reachable = false;
    }
    if (!reachable) {
      // ignore: avoid_print
      print('SKIPPED: $_backend is not reachable — live-only test.');
      return;
    }
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    auth = KeycloakAuthRepositoryImpl(keycloakBaseUrl: _keycloak);
    await auth.login(username: _agentUsername, password: _agentPassword);
    api = ApiClientImpl(httpClient: ApiHttpClient(baseUrl: _backend), authTokenProvider: auth);
    final client = (await api.fetchClients()).firstWhere((c) => c.name == 'Awash Bank');
    clientId = client.id;
    workflowId = (await api.fetchWorkflows(client.id)).firstWhere((w) => w.name == 'KYC/KYB collection').id;
    final dir = await Directory.systemTemp.createTemp('live_business_doc_');
    image = File('${dir.path}/document.png')..writeAsBytesSync(pngBytes);
  });

  Map<String, dynamic> individual(String salt) => {
        'personal_info.full_name': 'Ada Lovelace',
        'personal_info.mother_name': 'Anna Byron',
        'personal_info.nationality': 'Ethiopian',
        'personal_info.gender': 'female',
        'personal_info.birth_date': '1990-01-01',
        'personal_info.phone': '09${salt.padLeft(8, '0')}',
        'personal_info.national_id': salt.padLeft(16, '1'),
      };

  const business = {
    'business_info.business_type': 'registered',
    'business_info.business_name': 'አዲስ Trading PLC',
    'business_info.tin': '0012345678',
  };

  Future<String> newCase() async =>
      (await api.fetchFlowManifestStac(flowId: workflowId, clientId: clientId)).caseId;

  test('the manifest carries the business capture stage as a photo_capture, and the GLOBAL business_info stage', () async {
    if (!reachable) return;
    final manifest = await api.fetchFlowManifestStac(flowId: workflowId, clientId: clientId);
    final byId = {for (final s in manifest.stages) s['stageId'] as String: s};
    expect(byId['trade_license']!['nativeHandler'], 'photo_capture');
    expect((byId['trade_license']!['widget'] as Map)['type'], 'kneth_photo_capture');
    expect(byId.containsKey('business_info'), isTrue);
  });

  test('combined KYC+KYB submit returns BOTH ids; the individual and the business document each upload, 201, to their own route',
      () async {
    if (!reachable) return;
    final salt = (DateTime.now().millisecondsSinceEpoch % 100000000).toString();
    final caseId = await newCase();

    final result = await api.submitCase(caseId: caseId, values: {...individual(salt), ...business});
    expect(result.recordId, matches(_uuid));
    expect(result.businessRecordId, matches(_uuid), reason: 'Part 0.1: submit itself returns business_record_id');
    expect(result.recordId, isNot(result.businessRecordId));

    final id = await api.uploadDocument(recordId: result.recordId!, kind: 'identification_card', filePath: image.path);
    expect(id.kind, 'identification_card');
    final license =
        await api.uploadBusinessDocument(businessRecordId: result.businessRecordId!, kind: 'trade_license', filePath: image.path);
    expect(license.kind, 'trade_license');
    expect(license.fileReference, isNotEmpty);
    expect(license.id, isNot(id.id));

    // The pull endpoint agrees about which records this case owns.
    final pull = await http.get(Uri.parse('$_backend/cases/$caseId'), headers: {'Authorization': 'Bearer ${auth.currentToken()}'});
    final json = jsonDecode(pull.body) as Map<String, dynamic>;
    expect(json['business_record_id'], result.businessRecordId);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the whole sync sequence through SyncRepositoryImpl: combined case, both documents, SyncSucceeded', () async {
    if (!reachable) return;
    final salt = (DateTime.now().millisecondsSinceEpoch % 100000000 + 1).toString();
    final caseId = await newCase();

    final statuses = await SyncRepositoryImpl(apiClient: api)
        .submitCase(
          caseId: caseId,
          values: {...individual(salt), ...business},
          mediaFilesByStage: {'identification_card': image.path, 'trade_license': image.path},
        )
        .toList();

    expect(statuses.last, isA<SyncSucceeded>(), reason: '$statuses');
    expect(statuses.whereType<SyncUploading>().map((s) => s.label),
        ['Submitting case', 'Uploading identification_card', 'Uploading trade_license']);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('business-only case: no record_id, only the business document uploads; an individual document fails loudly',
      () async {
    if (!reachable) return;
    final caseId = await newCase();
    final statuses = await SyncRepositoryImpl(apiClient: api)
        .submitCase(caseId: caseId, values: business, mediaFilesByStage: {'trade_license': image.path})
        .toList();
    expect(statuses.last, isA<SyncSucceeded>(), reason: '$statuses');

    final result = await api.submitCase(caseId: await newCase(), values: business);
    expect(result.recordId, isNull, reason: 'no individual identity fields: no identity record');
    expect(result.businessRecordId, matches(_uuid));

    final failed = await SyncRepositoryImpl(apiClient: api)
        .submitCase(caseId: await newCase(), values: business, mediaFilesByStage: {'identification_card': image.path})
        .toList();
    expect(failed.last, isA<SyncFailed>());
    expect((failed.last as SyncFailed).exception.message, contains('recordId'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the backend rejects a kind on the wrong route (422) and an unknown business record (404), mapped to ClientException',
      () async {
    if (!reachable) return;
    final salt = (DateTime.now().millisecondsSinceEpoch % 100000000 + 2).toString();
    final result = await api.submitCase(caseId: await newCase(), values: {...individual(salt), ...business});

    await expectLater(
      api.uploadBusinessDocument(businessRecordId: result.businessRecordId!, kind: 'identification_card', filePath: image.path),
      throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 422)),
    );
    await expectLater(
      api.uploadDocument(recordId: result.recordId!, kind: 'trade_license', filePath: image.path),
      throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 422)),
    );
    await expectLater(
      api.uploadBusinessDocument(
          businessRecordId: '00000000-0000-0000-0000-000000000000', kind: 'trade_license', filePath: image.path),
      throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 404)),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
