// A genuinely LIVE test — real HTTP, real Postgres, real Keycloak, real Redis,
// nothing mocked at the transport level — driving the actual round trip
// through this app's own Dart code (KeycloakAuthRepositoryImpl,
// ApiClientImpl), not just curl against the backend directly.
//
// Correction (2026-09-24). NOTES.md's Phase 5 recorded that this file "could
// NOT actually be exercised": flutter_tester returned a synthetic 400 with an
// empty body for every real HTTP call, attributed to an environment-level
// restriction. That was wrong. `TestWidgetsFlutterBinding.ensureInitialized()`
// (needed here for flutter_secure_storage's channel) installs flutter_test's
// own `HttpOverrides`, which answers EVERY request with an empty 400 — set
// `HttpOverrides.global = null` and real HTTP works. Verified by a scratch
// test hitting /docs both ways (400/0 bytes vs 200/1018 bytes), and by this
// file then running for real against the seeded backend.
//
// Skips itself cleanly if the backend isn't reachable — this file is not,
// and must never become, a normal `flutter test`/CI dependency (see
// NOTES.md's Part 1a in the ApiClientImpl section for why a live backend
// is never assumed to be running). Run explicitly, in an environment
// without this restriction:
//   flutter test test/live/live_round_trip_test.dart
//
// Fixture data (client/workflow/agent) was seeded directly into Postgres
// for this one verification run, matching this app's own confirmed
// contract — see NOTES.md's Phase 5 for the exact seed shape and why
// seeding went straight to Postgres rather than through the API (agent
// bootstrapping is circular: creating the first agent needs an
// authenticated, already-assigned caller, and none exists yet).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sdui_demo/features/auth/data/keycloak_auth_repository_impl.dart';
import 'package:sdui_demo/services/api_client_impl.dart';
import 'package:sdui_demo/services/api_http_client.dart';

/// `flutter test`'s headless engine has no real native
/// flutter_secure_storage implementation registered, so the real plugin's
/// method channel would just fail — this test doesn't need persistence to
/// survive across runs anyway, only for `login()`'s own `_persist()` call
/// to succeed. Same fake shape as keycloak_auth_repository_impl_test.dart.
class _InMemorySecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => _values[key];

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      _values.containsKey(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => _values.clear();

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => Map.of(_values);
}

const _backendBaseUrl = 'http://127.0.0.1:8000';
const _keycloakBaseUrl = 'http://127.0.0.1:8080';

// From this run's own seed data (NOTES.md's Phase 5) — a real
// identity.agents row, linked to a real Keycloak user, assigned to a real
// seeded client/workflow. Not secrets in any real sense (a throwaway local
// dev realm), but still not a fixture to reuse against anything real.
const _agentUsername = '826dfc90-f28b-4dde-806e-f15ab51c8e84';
const _agentPassword = 'dev-agent-password-123';

Future<bool> _backendReachable() async {
  try {
    final response = await http.get(Uri.parse('$_backendBaseUrl/docs')).timeout(const Duration(seconds: 10));
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

void main() {
  // KeycloakAuthRepositoryImpl.login persists via FlutterSecureStorage,
  // whose platform channel needs a live Flutter binding even in a plain
  // (non-testWidgets) test.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  test('login -> fetchClients -> fetchWorkflows -> fetchFlowManifestStac -> submitCase -> uploadDocument, all real',
      () async {
    if (!await _backendReachable()) {
      // ignore: avoid_print
      print('SKIPPED: $_backendBaseUrl is not reachable — this is a live-only test, see its own doc comment.');
      return;
    }

    FlutterSecureStoragePlatform.instance = _InMemorySecureStoragePlatform();
    final authRepository = KeycloakAuthRepositoryImpl(keycloakBaseUrl: _keycloakBaseUrl);
    final apiClient = ApiClientImpl(
      httpClient: ApiHttpClient(baseUrl: _backendBaseUrl),
      authTokenProvider: authRepository,
    );

    // 1. Real Keycloak login (ROPC grant).
    final session = await authRepository.login(username: _agentUsername, password: _agentPassword);
    expect(session.accessToken, isNotEmpty);

    // 2. Real GET /clients — the agent's own seeded assignment.
    final clients = await apiClient.fetchClients();
    expect(clients, isNotEmpty);
    final client = clients.firstWhere((c) => c.name == 'Awash Bank');

    // 3. Real GET /clients/{id}/workflows.
    final workflows = await apiClient.fetchWorkflows(client.id);
    expect(workflows, isNotEmpty);
    final workflow = workflows.firstWhere((w) => w.name == 'KYC/KYB collection');

    // 4. Real POST /cases/flow-manifest/stac — a brand-new case.
    final manifest = await apiClient.fetchFlowManifestStac(flowId: workflow.id, clientId: client.id);
    expect(manifest.caseId, isNotEmpty);
    final stageIds = manifest.stages.map((s) => s['stageId']).toList();
    expect(stageIds, containsAll(['personal_info', 'identification_card', 'association_details']));

    // 5. Real POST /cases/{case_id}/submit — GLOBAL (personal_info) and
    // TENANT (association_details) values in one flat, dotted-key map,
    // exactly the shape SyncRepositoryImpl builds from FlowCaseState.allValues.
    final result = await apiClient.submitCase(
      caseId: manifest.caseId,
      values: {
        'personal_info.full_name': 'Ada Lovelace',
        'personal_info.mother_name': 'Anna Byron',
        'personal_info.nationality': 'Ethiopian',
        'personal_info.gender': 'female',
        'personal_info.birth_date': '1990-01-01',
        'personal_info.phone': '0911000000',
        'personal_info.national_id': '1234567890123456',
        'association_details.association_type': 'Individual',
      },
    );
    expect(result.caseId, manifest.caseId);
    expect(result.recordId, isNotNull);

    // 6. Real POST /identity/records/{record_id}/documents/identification_card
    // — a real multipart upload of a real (tiny, valid) PNG.
    final tempDir = await Directory.systemTemp.createTemp('live_round_trip_');
    addTearDown(() => tempDir.delete(recursive: true));
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    final photoFile = File('${tempDir.path}/identification_card.png')..writeAsBytesSync(pngBytes);

    final uploaded = await apiClient.uploadDocument(
      recordId: result.recordId!,
      kind: 'identification_card',
      filePath: photoFile.path,
    );
    expect(uploaded.kind, 'identification_card');
    expect(uploaded.fileReference, isNotEmpty);
  });
}
