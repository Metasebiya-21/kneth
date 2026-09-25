// LIVE tier: the backend-counted liveness attempt limit and the supervisor override, against the
// REAL running backend, database and Keycloak.
//
// Proves: the BACKEND counts (a brand-new client instance with no state, i.e. a force-quit and
// relaunch, still gets its fourth attempt refused with a 409); the third failed attempt moves the
// case to needs_manual_review and a submit is then refused; a plain agent cannot override (403); a
// supervisor assignment can, and the case then continues. Does NOT prove liveness detection works:
// no camera or face is involved, and the "device verdicts" are hand-written.
//
// The override steps use REAL identities: the dev agent (who works the case) and the seeded dev
// platform admin (tool/seed_dev_platform_admin.sh), whom the test grants a supervisor/admin
// assignment through the real admin route and revokes afterwards; the dev agent's own role is
// changed through the same route and restored.
//
//   flutter test test/live/liveness_attempts_live_test.dart      (or: make live)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sdui_demo/features/auth/data/keycloak_auth_repository_impl.dart';
import 'package:sdui_demo/services/api_client_impl.dart';
import 'package:sdui_demo/services/api_http_client.dart';
import 'package:sdui_demo/services/app_exception.dart';

const _backend = 'http://127.0.0.1:8000';
const _keycloak = 'http://127.0.0.1:8080';
const _agentUsername = '826dfc90-f28b-4dde-806e-f15ab51c8e84';
const _agentPassword = 'dev-agent-password-123';
const _clientIdInDb = 'e8ce7cac-22fb-4858-8328-bd62297c7e75';

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
  late String clientId;
  late String workflowId;

  Future<(ApiClientImpl, KeycloakAuthRepositoryImpl)> freshLoginFor(String username, String password) async {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    final auth = KeycloakAuthRepositoryImpl(keycloakBaseUrl: _keycloak);
    await auth.login(username: username, password: password);
    return (ApiClientImpl(httpClient: ApiHttpClient(baseUrl: _backend), authTokenProvider: auth), auth);
  }

  /// A brand-new client with no state at all: a relaunched app.
  Future<(ApiClientImpl, KeycloakAuthRepositoryImpl)> freshLaunch() => freshLoginFor(_agentUsername, _agentPassword);

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
    final (api, _) = await freshLaunch();
    final client = (await api.fetchClients()).firstWhere((c) => c.name == 'Awash Bank');
    clientId = client.id;
    workflowId = (await api.fetchWorkflows(client.id)).firstWhere((w) => w.name == 'KYC/KYB collection').id;
  });

  Future<void> failAnAttempt(ApiClientImpl api, String caseId, {String session = 's'}) async {
    final begun = await api.beginLivenessAttempt(caseId);
    await api.recordLivenessAttemptOutcome(
      caseId: caseId,
      attemptId: begun.attemptId,
      attestedLivenessVerdict: false,
      attestedAntiSpoofingFlags: const {'motionCorrelationCheckFailed': true},
      attestedSessionId: session,
    );
  }

  test('force-quit and relaunch: three counted attempts, the fourth refused by the backend, the case sent to review',
      () async {
    if (!reachable) return;
    final (first, _) = await freshLaunch();
    final caseId = (await first.fetchFlowManifestStac(flowId: workflowId, clientId: clientId)).caseId;

    // Launch 1: begin (open), "force-quit" before reporting anything, then begin again -> the SAME attempt.
    final begun = await first.beginLivenessAttempt(caseId);
    expect(begun.attemptNumber, 1);
    final (second, _) = await freshLaunch();
    final again = await second.beginLivenessAttempt(caseId);
    expect(again.attemptId, begun.attemptId, reason: 'a relaunch mid-attempt does not burn or bypass an attempt');

    // Report it, then two more, each from a fresh launch with no local state.
    await second.recordLivenessAttemptOutcome(
      caseId: caseId,
      attemptId: again.attemptId,
      attestedLivenessVerdict: false,
      attestedAntiSpoofingFlags: const {'motionCorrelationCheckFailed': true},
    );
    final (third, _) = await freshLaunch();
    await failAnAttempt(third, caseId);
    final (fourthLaunch, _) = await freshLaunch();
    final lastBegun = await fourthLaunch.beginLivenessAttempt(caseId);
    expect(lastBegun.attemptNumber, 3);
    final afterThird = await fourthLaunch.recordLivenessAttemptOutcome(
      caseId: caseId,
      attemptId: lastBegun.attemptId,
      attestedLivenessVerdict: false,
      attestedAntiSpoofingFlags: const {'motionCorrelationCheckFailed': true},
    );
    expect(afterThird.caseStatus, 'needs_manual_review');
    expect(afterThird.attemptsRemaining, 0);

    // A brand-new launch: the fourth attempt is refused by the backend.
    final (fifthLaunch, _) = await freshLaunch();
    await expectLater(
      fifthLaunch.beginLivenessAttempt(caseId),
      throwsA(isA<ClientException>()
          .having((e) => e.statusCode, 'status', 409)
          .having((e) => e.message, 'message', contains('manual review'))),
    );
    final status = await fifthLaunch.fetchLivenessStatus(caseId);
    expect(status.attemptsUsed, 3);
    expect(status.caseStatus, 'needs_manual_review');
    expect(status.attestedPassRecorded, isFalse);

    // The database agrees, and a case awaiting review cannot be submitted.
    final row = await _sql("select status from \"case\".cases where id = '$caseId'");
    if (row != null) expect(row, 'needs_manual_review');
    await expectLater(
      fifthLaunch.submitCase(caseId: caseId, values: const {}),
      throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 412)),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a pass is recorded as an attested pass and ends the need for attempts', () async {
    if (!reachable) return;
    final (api, _) = await freshLaunch();
    final caseId = (await api.fetchFlowManifestStac(flowId: workflowId, clientId: clientId)).caseId;
    final begun = await api.beginLivenessAttempt(caseId);
    final status = await api.recordLivenessAttemptOutcome(
      caseId: caseId,
      attemptId: begun.attemptId,
      attestedLivenessVerdict: true,
      attestedAntiSpoofingFlags: const {'motionCorrelationCheckFailed': false},
    );
    expect(status.attestedPassRecorded, isTrue);
    expect(status.caseStatus, 'in_progress');
    await expectLater(api.beginLivenessAttempt(caseId), throwsA(isA<ClientException>()));
  }, timeout: const Timeout(Duration(minutes: 2)));

  // The reviewer in these tests is a REAL second identity: the seeded dev platform admin
  // (tool/seed_dev_platform_admin.sh), given a client assignment through the real admin route and
  // revoked afterwards. The dev agent's own role is changed through the real route and restored.
  const adminAgentId = '5c1a7d2e-0b6a-4e57-9a11-7f0d0e5a0001';
  const devAgentId = '826dfc90-f28b-4dde-806e-f15ab51c8e84';

  Future<String> tokenFor(String username, String password) async {
    final (_, auth) = await freshLoginFor(username, password);
    return auth.currentToken()!;
  }

  Map<String, String> bearer(String token) => {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  Future<http.Response> adminCall(String method, String path, [Map<String, dynamic>? body]) async {
    final admin = await tokenFor('dev-platform-admin', 'dev-platform-admin-password-123');
    final uri = Uri.parse('$_backend$path');
    return switch (method) {
      'POST' => http.post(uri, headers: bearer(admin), body: jsonEncode(body)),
      'PUT' => http.put(uri, headers: bearer(admin), body: jsonEncode(body)),
      _ => http.delete(uri, headers: bearer(admin)),
    };
  }

  test('override: a plain agent is refused; the agent who worked the case is refused even as supervisor or admin; '
      'a DIFFERENT supervisor or admin (a real second identity) succeeds', () async {
    if (!reachable) return;
    final (api, auth) = await freshLaunch();
    final caseId = (await api.fetchFlowManifestStac(flowId: workflowId, clientId: clientId)).caseId;
    for (var i = 0; i < 3; i++) {
      await failAnAttempt(api, caseId);
    }
    expect((await api.fetchLivenessStatus(caseId)).caseStatus, 'needs_manual_review');

    Future<http.Response> override(String token, Map<String, dynamic> body) => http.post(
          Uri.parse('$_backend/cases/$caseId/liveness-override'),
          headers: bearer(token),
          body: jsonEncode(body),
        );
    const good = {'method': 'physical_document_review', 'decision': 'accepted', 'note': 'live test: original ID card seen'};
    final devToken = auth.currentToken()!;

    // A plain `agent` assignment: refused by the role check.
    final denied = await override(devToken, good);
    expect(denied.statusCode, 403);
    expect(jsonDecode(denied.body)['message'], contains('role for client'));

    const assignmentUrl = '/operations/agents/$devAgentId/clients/$_clientIdInDb/assignment';
    try {
      // The SAME agent, promoted to supervisor (then admin) through the real admin route, worked this
      // case (created it and ran the attempts): refused by the self-review guard, with its own message.
      for (final role in ['supervisor', 'admin']) {
        expect((await adminCall('PUT', assignmentUrl, {'role': role})).statusCode, 200, reason: role);
        final selfReview = await override(devToken, good);
        expect(selfReview.statusCode, 403, reason: role);
        expect(jsonDecode(selfReview.body)['message'], contains('cannot override a case you worked on'), reason: role);
        expect(jsonDecode(selfReview.body)['message'], isNot(contains('role for client')), reason: role);
      }
    } finally {
      await adminCall('PUT', assignmentUrl, {'role': 'agent'});
    }
    expect((await api.fetchLivenessStatus(caseId)).caseStatus, 'needs_manual_review');

    // A real different identity: the platform admin user, given a supervisor assignment for the client.
    final reviewer = await tokenFor('dev-platform-admin', 'dev-platform-admin-password-123');
    expect(
        (await adminCall('POST', '/operations/assignments',
                {'agent_id': adminAgentId, 'client_id': _clientIdInDb, 'role': 'supervisor'}))
            .statusCode,
        201);
    try {
      // Deferred methods are named and refused, not silently accepted.
      final deferred = await override(reviewer, {...good, 'method': 'video_call'});
      expect(deferred.statusCode, 422);
      expect(jsonDecode(deferred.body)['message'], contains('not built yet'));

      final ok = await override(reviewer, good);
      expect(ok.statusCode, 201, reason: ok.body);
      expect(jsonDecode(ok.body)['case_status'], 'in_progress');
    } finally {
      await adminCall('DELETE', '/operations/agents/$adminAgentId/clients/$_clientIdInDb/assignment');
    }

    final status = await api.fetchLivenessStatus(caseId);
    expect(status.override?.method, 'physical_document_review');
    expect(status.override?.decision, 'accepted');
    expect(status.caseStatus, 'in_progress');
    await expectLater(api.beginLivenessAttempt(caseId), throwsA(isA<ClientException>()), reason: 'no fresh attempts');
    final submitted = await api.submitCase(caseId: caseId, values: const {});
    expect(submitted.caseId, caseId, reason: 'the case can continue once a supervisor accepted it');

    final stored = await _sql("select method || '|' || decision from \"case\".liveness_overrides where case_id = '$caseId'");
    if (stored != null) expect(stored, 'physical_document_review|accepted');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an admin assignment (a real second identity) may override too', () async {
    if (!reachable) return;
    final (api, _) = await freshLaunch();
    final caseId = (await api.fetchFlowManifestStac(flowId: workflowId, clientId: clientId)).caseId;
    for (var i = 0; i < 3; i++) {
      await failAnAttempt(api, caseId);
    }
    final reviewer = await tokenFor('dev-platform-admin', 'dev-platform-admin-password-123');
    expect(
        (await adminCall('POST', '/operations/assignments',
                {'agent_id': adminAgentId, 'client_id': _clientIdInDb, 'role': 'admin'}))
            .statusCode,
        201);
    try {
      final ok = await http.post(
        Uri.parse('$_backend/cases/$caseId/liveness-override'),
        headers: bearer(reviewer),
        body: jsonEncode({'method': 'physical_document_review', 'decision': 'accepted'}),
      );
      expect(ok.statusCode, 201, reason: ok.body);
    } finally {
      await adminCall('DELETE', '/operations/agents/$adminAgentId/clients/$_clientIdInDb/assignment');
    }
    expect((await api.fetchLivenessStatus(caseId)).caseStatus, 'in_progress');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
