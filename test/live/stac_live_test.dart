// LIVE tier: the scripted Stac-flow scenarios against the REAL running backend: real
// Keycloak login, real POST /cases/flow-manifest/stac (creates a case and returns its real
// case_id, its stages and their widget trees: the only manifest route the app uses), real
// reference-data-backed live options, real POST /cases/{id}/submit, and the real pull
// endpoint. The length and Unicode scenarios are compared with the goldens recorded from
// the previous renderer (test/fixtures/golden/), which contain no backend-specific ids.
//
// Skips itself when the backend isn't reachable (like live_round_trip_test.dart). Needs
// the seeds in tool/ (STAC_MIGRATION_SCOPING.md). Real network I/O inside flutter_test
// needs `HttpOverrides.global = null` (flutter_test otherwise answers every request with
// an empty 400, which NOTES.md's Phase 5 had mistaken for an environment restriction).
//
//   flutter test test/live/stac_live_test.dart      (or: make live)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:sdui_demo/features/auth/data/backend_auth_repository_impl.dart';
import 'package:sdui_demo/features/flow/data/flow_repository_impl.dart';
import 'package:sdui_demo/features/flow/data/stac_manifest_mapper.dart';
import 'package:sdui_demo/features/flow/domain/flow_case_state.dart';
import 'package:sdui_demo/features/flow/domain/flow_manifest.dart';
import 'package:sdui_demo/features/flow/domain/load_flow_case_use_case.dart';
import 'package:sdui_demo/features/sync/data/sync_repository_impl.dart';
import 'package:sdui_demo/features/sync/domain/sync_status.dart';
import 'package:sdui_demo/services/api_client_impl.dart';
import 'package:sdui_demo/services/api_http_client.dart';

import '../support/stac_flow_harness.dart';
import '../support/stac_scenarios.dart';

const _backend = 'http://127.0.0.1:8000';
const _agentUsername = 'tagent';
const _agentPassword = 'test#123';
const _stageIds = ['association_details', 'location'];

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
  late ApiClientImpl realClient;
  late BackendAuthRepositoryImpl auth;
  late String clientId;
  late String workflowId;

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
    realClient = ApiClientImpl(httpClient: ApiHttpClient(baseUrl: _backend), authTokenProvider: auth);
    final client = (await realClient.fetchClients()).firstWhere((c) => c.name == 'Awash Bank');
    clientId = client.id;
    workflowId = (await realClient.fetchWorkflows(client.id)).firstWhere((w) => w.name == 'KYC/KYB collection').id;
  });

  Map<String, dynamic> golden(String name) {
    final all = jsonDecode(File('test/fixtures/golden/scenario_golden.json').readAsStringSync()) as Map<String, dynamic>;
    return (all[name] as Map).cast<String, dynamic>();
  }

  /// One complete run of [stageIds] on a brand-new real case, driven by [script].
  Future<(ScenarioRun, InFlightCountingApiClient, String)> liveRun(
    WidgetTester tester,
    Future<void> Function(WidgetTester, ScenarioRun, InFlightCountingApiClient) script, {
    List<String> stageIds = _stageIds,
  }) async {
    final counting = InFlightCountingApiClient(realClient);
    // Creates a real case through the (only) manifest route and returns its real case_id.
    final created = await tester.runAsync(() => realClient.fetchFlowManifestStac(flowId: workflowId, clientId: clientId));
    final stages = [for (final id in stageIds) created!.stages.firstWhere((s) => s['stageId'] == id)];
    final run = ScenarioRun();
    await tester.pumpWidget(stacFlowApp(
      apiClient: counting,
      stacStages: stages,
      workflowId: workflowId,
      clientId: clientId,
      caseId: created!.caseId,
    ));
    await settle(tester, live: counting);
    await script(tester, run, counting);
    await drainIdleConnectionTimers(tester);
    return (run, counting, created.caseId);
  }

  testWidgets('association_details + location against the real backend: conditional, cascade with real UUIDs, submit',
      (tester) async {
    if (!reachable) return;
    final (run, calls, caseId) = await liveRun(tester, (t, r, live) async {
      await associationScenario(t, r, live: live);
      await locationScenario(t, r, live: live);
    });

    expect(run.log, contains('assoc: company_name shown after Group = true'));
    expect(run.log, contains('assoc: advanced past the stage = true'));
    expect(calls.errors, isEmpty, reason: 'no request failed: the real backend accepted the region UUID');
    expect(run.log, contains('loc: district options after region = [Bole, Kirkos, Yeka]'));
    expect(run.completed, isTrue);
    expect(run.allValues['location.region'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(run.allValues['location.district'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(run.allValues['location.postal_code'], '1000');
    expect(run.allValues['association_details.association_type'], 'Group');
    expect(run.allValues['association_details.company_name'], 'Acme');

    final result = await tester.runAsync(() => realClient.submitCase(caseId: caseId, values: run.allValues));
    expect(result!.caseId, caseId);
    expect(result.status, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('a value typed then hidden is dropped, and the payload is accepted by the real backend', (tester) async {
    if (!reachable) return;
    final (run, _, caseId) = await liveRun(tester, (t, r, live) async {
      await choose(t, 'Group', dropdown: 0, live: live);
      await t.enterText(textFieldWith('company_name'), 'Acme');
      await choose(t, 'Individual', dropdown: 0, live: live);
      await pressContinue(t, live: live);
      captureResult(t, r);
    }, stageIds: ['association_details']);

    expect(run.allValues, {'association_details.association_type': 'Individual'});
    final result = await tester.runAsync(() => realClient.submitCase(caseId: caseId, values: run.allValues));
    expect(result!.caseId, caseId);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('length bounds from the real manifest: identical to the golden recorded from the previous renderer',
      (tester) async {
    if (!reachable) return;
    final (run, _, caseId) = await liveRun(tester, (t, r, live) => lengthScenario(t, r, live: live), stageIds: ['length_rules']);

    expect(run.notes, (golden('length_rules')['notes'] as Map).cast<String, dynamic>());
    expect(run.log, (golden('length_rules')['log'] as List).cast<String>());
    final result = await tester.runAsync(() => realClient.submitCase(caseId: caseId, values: run.allValues));
    expect(result!.caseId, caseId);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('unicode_rules against the real backend: identical to the golden, Amharic accepted', (tester) async {
    if (!reachable) return;
    final (run, _, caseId) =
        await liveRun(tester, (t, r, live) => unicodeScenario(t, r, live: live), stageIds: ['unicode_rules']);

    expect(run.notes, (golden('unicode_rules')['notes'] as Map).cast<String, dynamic>());
    expect(run.log, (golden('unicode_rules')['log'] as List).cast<String>());
    expect(run.allValues['unicode_rules.am_name'], 'አበበ በቀለ');
    final result = await tester.runAsync(() => realClient.submitCase(caseId: caseId, values: run.allValues));
    expect(result!.caseId, caseId);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('Amharic + emoji, submitted by the mobile client and read back through the real pull endpoint, exactly',
      (tester) async {
    if (!reachable) return;
    final manifest = await tester.runAsync(() => realClient.fetchFlowManifestStac(flowId: workflowId, clientId: clientId));
    const sent = {
      'unicode_rules.am_name': 'አበበ በቀለ',
      'unicode_rules.single_char': '\u{1F600}',
      'unicode_rules.opt_code': '123',
    };
    await tester.runAsync(() => realClient.submitCase(caseId: manifest!.caseId, values: sent));

    // Read back exactly the way the app's own HTTP layer decodes a response (package:http, response.body).
    final response = await tester.runAsync(() => http.get(
          Uri.parse('$_backend/cases/${manifest!.caseId}'),
          headers: {'Authorization': 'Bearer ${auth.currentToken()}'},
        ));
    expect(response!.statusCode, 200);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final stored = {
      for (final v in (json['stage_field_values'] as List).cast<Map<String, dynamic>>())
        '${v['stage_key']}.${v['field_key']}': v['value'],
    };
    expect(stored, sent);
    for (final value in sent.values) {
      expect(utf8.decode(response.bodyBytes), contains(value));
      expect(response.bodyBytes, containsAllInOrder(utf8.encode(value)));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('full flow through the new data source, live: start (real case) -> resume (fresh, then stale by case_id) -> submit',
      () async {
    if (!reachable) return;
    SharedPreferences.setMockInitialValues({});
    final repository = FlowRepositoryImpl(apiClient: realClient);
    final useCase = LoadFlowCaseUseCase(repository);
    final flow = FlowManifest(workflowId: workflowId, clientId: clientId);
    final uuid = RegExp(r'^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$');

    // START: the no-case_id path creates a case and returns its real case_id.
    final started = await useCase.start(flow);
    final caseId = started.manifest.caseId;
    expect(caseId, matches(uuid));
    expect(started.manifest.stages.map((s) => s.stageId),
        containsAllInOrder(['personal_info', 'identification_card', 'association_details', 'location']));
    expect(started.manifest.stagesJson.every(stageJsonHasWidget), isTrue);
    expect((await useCase.start(flow)).manifest.caseId, isNot(caseId), reason: 'each start is a NEW case');

    // Progress through two stages, save, and RESUME while fresh: returned untouched, no request needed.
    var state = started.advanced({'full_name': 'Ada'}).advanced({'filePath': '/tmp/none.png'});
    expect(state.currentStage.stageId, 'association_details');
    await repository.saveCaseState(state);
    final fresh = await useCase.resume(flow);
    expect(fresh!.manifest.caseId, caseId);
    expect(fresh.stageIndex, 2);

    // RESUME after the manifest went stale: refreshed from the real backend BY ITS OWN case_id.
    final aged = FlowCaseState(
      manifest: ResolvedFlowManifest(
        workflowId: state.manifest.workflowId,
        clientId: state.manifest.clientId,
        caseId: caseId,
        fetchedAt: DateTime.now().subtract(const Duration(hours: 25)),
        stagesJson: state.manifest.stagesJson,
      ),
      stageIndex: state.stageIndex,
      isComplete: false,
      collectedValues: state.collectedValues,
    );
    await repository.saveCaseState(aged);
    final resumed = (await useCase.resume(flow))!;
    expect(resumed.manifest.caseId, caseId, reason: 'the backend resumed the same case, not a new one');
    expect(resumed.manifest.isStale, isFalse);
    expect(resumed.stageIndex, 2, reason: 'the agent keeps their place');
    expect(resumed.collectedValues['personal_info'], {'full_name': 'Ada'}, reason: 'and their answers');
    expect(resumed.manifest.stagesJson, state.manifest.stagesJson,
        reason: 'the backend returns the case\'s FROZEN stages, identical to what start returned');

    // SUBMIT the rest of the way, through the real SyncRepositoryImpl.
    state = resumed.advanced({'association_type': 'Individual'});
    expect(state.currentStage.stageId, 'location');
    final statuses = await SyncRepositoryImpl(apiClient: realClient)
        .submitCase(caseId: caseId, values: state.allValues, mediaFilesByStage: const {})
        .toList();
    expect(statuses.last, isA<SyncSucceeded>());
  }, timeout: const Timeout(Duration(minutes: 2)));
}
