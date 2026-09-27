// LIVE tier: assignment accountability against the REAL running backend, database and Keycloak.
//
// One role per (agent, client), and the platform-admin-only routes to change or revoke an assignment,
// with the append-only audit log they write: grant -> duplicate refused -> update -> revoke -> audit read.
// Needs tool/seed_dev_platform_admin.sh (a Keycloak `platform_admin` user); skips itself if the
// backend is unreachable. The target agent is a random id (assignments hold logical references, so no
// real agent is disturbed) and the real Awash Bank client id.
//
//   flutter test test/live/assignment_management_live_test.dart      (or: make live)
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sdui_demo/features/auth/data/backend_auth_repository_impl.dart';

const _backend = 'http://127.0.0.1:8000';
const _clientId = 'e8ce7cac-22fb-4858-8328-bd62297c7e75';
const _adminAgentId = '5c1a7d2e-0b6a-4e57-9a11-7f0d0e5a0001';

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

String _uuid() {
  final random = Random.secure();
  final r = List.generate(32, (_) => random.nextInt(16).toRadixString(16));
  r[12] = '4';
  r[16] = 'a';
  return '${r.sublist(0, 8).join()}-${r.sublist(8, 12).join()}-${r.sublist(12, 16).join()}-${r.sublist(16, 20).join()}-${r.sublist(20, 32).join()}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool reachable;

  Future<String> loginAs(String username, String password) async {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
    final auth = BackendAuthRepositoryImpl(baseUrl: _backend);
    await auth.login(username: username, password: password);
    return auth.currentToken()!;
  }

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
    }
  });

  test('grant -> duplicate refused -> update -> revoke -> audit-log read, all attributable to the platform admin', () async {
    if (!reachable) return;
    final admin = await loginAs('dev-platform-admin', 'dev-platform-admin-password-123');
    Map<String, String> h(String t) => {'Authorization': 'Bearer $t', 'Content-Type': 'application/json'};
    final target = _uuid();
    final url = '$_backend/operations/agents/$target/clients/$_clientId/assignment';

    final grant = await http.post(Uri.parse('$_backend/operations/assignments'),
        headers: h(admin), body: jsonEncode({'agent_id': target, 'client_id': _clientId, 'role': 'agent'}));
    expect(grant.statusCode, 201, reason: grant.body);

    // One role per client: a second grant is a 409 and changes nothing.
    final duplicate = await http.post(Uri.parse('$_backend/operations/assignments'),
        headers: h(admin), body: jsonEncode({'agent_id': target, 'client_id': _clientId, 'role': 'supervisor'}));
    expect(duplicate.statusCode, 409);

    final update = await http.put(Uri.parse(url), headers: h(admin), body: jsonEncode({'role': 'supervisor'}));
    expect(update.statusCode, 200, reason: update.body);
    expect(jsonDecode(update.body)['role'], 'supervisor');

    final access = '$_backend/operations/agents/$target/clients/$_clientId/access';
    expect(jsonDecode((await http.get(Uri.parse(access), headers: h(admin))).body)['allowed'], isTrue);

    final revoke = await http.delete(Uri.parse(url), headers: h(admin));
    expect(revoke.statusCode, 200, reason: revoke.body);
    expect(jsonDecode(revoke.body)['role'], 'supervisor', reason: 'returns what was revoked');
    expect(jsonDecode((await http.get(Uri.parse(access), headers: h(admin))).body)['allowed'], isFalse);
    expect((await http.delete(Uri.parse(url), headers: h(admin))).statusCode, 404);

    final log = jsonDecode((await http.get(
      Uri.parse('$_backend/operations/assignment-audit-log?agent_id=$target&client_id=$_clientId'),
      headers: h(admin),
    ))
        .body) as List;
    expect(
      [for (final e in log) '${e['action']}:${e['previous_role']}->${e['new_role']}:${e['performed_by_agent_id']}'],
      [
        'granted:null->agent:$_adminAgentId',
        'role_changed:agent->supervisor:$_adminAgentId',
        'revoked:supervisor->null:$_adminAgentId',
      ],
      reason: 'a refused duplicate and a 404 revoke left no entries',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the same routes are refused for the ordinary dev agent (a plain agent, not a platform admin)', () async {
    if (!reachable) return;
    final agent = await loginAs('tagent', 'test#123');
    final headers = {'Authorization': 'Bearer $agent', 'Content-Type': 'application/json'};
    final target = _uuid();
    final url = '$_backend/operations/agents/$target/clients/$_clientId/assignment';
    expect((await http.put(Uri.parse(url), headers: headers, body: jsonEncode({'role': 'admin'}))).statusCode, 403);
    expect((await http.delete(Uri.parse(url), headers: headers)).statusCode, 403);
    expect((await http.get(Uri.parse('$_backend/operations/assignment-audit-log'), headers: headers)).statusCode, 403);
    expect(
        (await http.post(Uri.parse('$_backend/operations/assignments'),
                headers: headers, body: jsonEncode({'agent_id': target, 'client_id': _clientId, 'role': 'agent'})))
            .statusCode,
        403);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
