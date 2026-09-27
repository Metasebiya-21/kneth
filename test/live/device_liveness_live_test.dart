// LIVE tier: the device-attested liveness path against the REAL running backend and database.
//
// What this proves: the wire contract, that the backend records the device's claim as
// `attested_passed`/`attested_failed` (never `passed`), and that an attested claim has NONE of the
// side effects a real verification has (no golden-record provenance marked verified, no matching
// re-queued). What it does NOT and cannot prove: that liveness detection works. No camera, sensor
// or face is involved; the "device verdict" here is a hand-written value.
//
// The database assertions shell out to `docker exec postgres psql` (the dev database, as in
// tool/*.sql) and are skipped, with a printed notice, if that is not available.
//
//   flutter test test/live/device_liveness_live_test.dart      (or: make live)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sdui_demo/features/auth/data/backend_auth_repository_impl.dart';
import 'package:sdui_demo/features/sync/data/sync_repository_impl.dart';
import 'package:sdui_demo/features/sync/domain/sync_status.dart';
import 'package:sdui_demo/services/api_client_impl.dart';
import 'package:sdui_demo/services/api_http_client.dart';

const _backend = 'http://127.0.0.1:8000';
const _agentUsername = 'tagent';
const _agentPassword = 'test#123';

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

/// Runs one query against the dev database; null if docker/psql is not usable here.
Future<String?> _sql(String query) async {
  try {
    final r = await Process.run('docker', ['exec', 'postgres', 'psql', '-U', 'onboarding', '-d', 'onboarding', '-tA', '-c', query]);
    return r.exitCode == 0 ? (r.stdout as String).trim() : null;
  } catch (_) {
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool reachable;
  late ApiClientImpl api;
  late BackendAuthRepositoryImpl auth;
  late String clientId;
  late String workflowId;
  late File image;

  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );
  const flags = {
    'screenGlareDetected': true, // informational: recorded, never blocking
    'lackOfFacialContoursDetected': false,
    'motionCorrelationCheckFailed': false,
    'screenFlashSpoofDetected': false,
    'depthSpoofDetected': false,
  };

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
    auth = BackendAuthRepositoryImpl(baseUrl: _backend);
    await auth.login(username: _agentUsername, password: _agentPassword);
    api = ApiClientImpl(httpClient: ApiHttpClient(baseUrl: _backend), authTokenProvider: auth);
    final client = (await api.fetchClients()).firstWhere((c) => c.name == 'Awash Bank');
    clientId = client.id;
    workflowId = (await api.fetchWorkflows(client.id)).firstWhere((w) => w.name == 'KYC/KYB collection').id;
    final dir = await Directory.systemTemp.createTemp('live_device_liveness_');
    image = File('${dir.path}/selfie.png')..writeAsBytesSync(pngBytes);
  });

  Map<String, dynamic> individual(String salt) => {
        'personal_info.full_name': 'Ada Lovelace',
        'personal_info.mother_name': 'Anna Byron',
        'personal_info.nationality': 'Ethiopian',
        'personal_info.gender': 'female',
        'personal_info.birth_date': '1990-01-01',
        'personal_info.phone': '09${salt.padLeft(8, '0')}',
        'personal_info.national_id': salt.padLeft(16, '2'),
      };

  Future<String> newCaseWithRecord(String salt) async {
    final manifest = await api.fetchFlowManifestStac(flowId: workflowId, clientId: clientId);
    final result = await api.submitCase(caseId: manifest.caseId, values: individual(salt));
    return result.recordId!;
  }

  test('the manifest carries the selfie stage as kneth_liveness_capture with the liveness_capture handler', () async {
    if (!reachable) return;
    final manifest = await api.fetchFlowManifestStac(flowId: workflowId, clientId: clientId);
    final stage = manifest.stages.firstWhere((s) => s['stageId'] == 'selfie_liveness');
    expect(stage['nativeHandler'], 'liveness_capture');
    expect((stage['widget'] as Map)['type'], 'kneth_liveness_capture');
  });

  test('the claim is recorded as attested_passed, with none of a real verification\'s side effects', () async {
    if (!reachable) return;
    final salt = (DateTime.now().millisecondsSinceEpoch % 100000000).toString();
    final recordId = await newCaseWithRecord(salt);
    final goldenQuery = "from identity.golden_records g join identity.records r on r.golden_id = g.id where r.id = '$recordId'";
    final requeuedBefore = await _sql(
        "select count(*) from identity.resolution_outbox o join identity.records r on r.golden_id = o.golden_id "
        "where r.id = '$recordId' and o.reason = 'verification_updated'");

    final result = await api.submitAttestedLiveness(
      recordId: recordId,
      attestedLivenessVerdict: true,
      attestedAntiSpoofingFlags: flags,
      attestedSessionId: 'live-session-1',
      attestedDetector: 'smart_liveliness_detection 0.3.9',
    );
    expect(result.result, 'attested_passed');
    expect(result.provider, 'device-attested-liveness');

    final row = await _sql(
        "select v.result || '|' || v.provider || '|' || (v.raw_response->'attested_anti_spoofing_flags'->>'screenGlareDetected') "
        "|| '|' || (v.raw_response->>'attested_session_id') from identity.verifications v "
        "join identity.personal_verifications p on p.id = v.id where p.record_id = '$recordId'");
    if (row == null) {
      // ignore: avoid_print
      print('SKIPPED database assertions: docker exec postgres psql is not usable here.');
      return;
    }
    expect(row, 'attested_passed|device-attested-liveness|true|live-session-1');

    // No side effects: nothing marked verified in the golden record, no matching re-queued.
    expect(await _sql("select count(*) $goldenQuery and g.field_provenance->'national_id'->>'verified' = 'true'"), '0');
    expect(
        await _sql("select count(*) from identity.resolution_outbox o join identity.records r on r.golden_id = o.golden_id "
            "where r.id = '$recordId' and o.reason = 'verification_updated'"),
        requeuedBefore);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the selfie image uploads as a profile_picture against the same record', () async {
    if (!reachable) return;
    final salt = (DateTime.now().millisecondsSinceEpoch % 100000000 + 1).toString();
    final recordId = await newCaseWithRecord(salt);

    final uploaded = await api.uploadDocument(recordId: recordId, kind: 'profile_picture', filePath: image.path);
    expect(uploaded.kind, 'profile_picture');
    expect(uploaded.fileReference, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the whole sync sequence: submit, profile_picture upload, attested claim, SyncSucceeded', () async {
    if (!reachable) return;
    final salt = (DateTime.now().millisecondsSinceEpoch % 100000000 + 2).toString();
    final manifest = await api.fetchFlowManifestStac(flowId: workflowId, clientId: clientId);

    final statuses = await SyncRepositoryImpl(apiClient: api)
        .submitCase(
          caseId: manifest.caseId,
          values: individual(salt),
          mediaFilesByStage: {'selfie_liveness': image.path},
          attestedLivenessByStage: {
            'selfie_liveness': {
              'attestedLivenessVerdict': true,
              'attestedAntiSpoofingFlags': flags,
              'attestedSessionId': 'live-session-2',
              'attestedDetector': 'smart_liveliness_detection 0.3.9',
              'attestedAttemptsUsed': 1,
            },
          },
        )
        .toList();

    expect(statuses.last, isA<SyncSucceeded>(), reason: '$statuses');
    expect(statuses.whereType<SyncUploading>().map((s) => s.label), [
      'Submitting case',
      'Uploading selfie_liveness',
      'Recording device-attested liveness (selfie_liveness)',
    ]);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an unknown provider key is a clean 404 from the real backend; the mock "liveness" key is untouched', () async {
    if (!reachable) return;
    final salt = (DateTime.now().millisecondsSinceEpoch % 100000000 + 3).toString();
    final recordId = await newCaseWithRecord(salt);
    Future<http.Response> post(String key) => http.post(
          Uri.parse('$_backend/identity/records/$recordId/verifications/$key'),
          headers: {'Authorization': 'Bearer ${auth.currentToken()}', 'Content-Type': 'application/json'},
          body: jsonEncode({'field_checked': 'liveness', 'payload': {}}),
        );

    final unknown = await post('device_livenes');
    expect(unknown.statusCode, 404);
    expect(jsonDecode(unknown.body)['message'], contains('device_liveness'));

    final mock = await post('liveness');
    expect(mock.statusCode, 201);
    expect(jsonDecode(mock.body)['provider'], 'mock-liveness');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a malformed claim (the un-attested spelling) is refused by the real backend with 422', () async {
    if (!reachable) return;
    final salt = (DateTime.now().millisecondsSinceEpoch % 100000000 + 4).toString();
    final recordId = await newCaseWithRecord(salt);
    final response = await http.post(
      Uri.parse('$_backend/identity/records/$recordId/verifications/device_liveness'),
      headers: {'Authorization': 'Bearer ${auth.currentToken()}', 'Content-Type': 'application/json'},
      body: jsonEncode({'field_checked': 'liveness', 'payload': {'passed': true}}),
    );
    expect(response.statusCode, 422);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
