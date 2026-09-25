// The scripted Stac-flow scenarios, OFFLINE (runs in `make ci`), asserted against the
// GOLDEN observations recorded from the previous renderer while it still existed
// (test/fixtures/golden/scenario_golden.json, STAC_MIGRATION_SCOPING.md section 14.5).
// The old-vs-Stac comparison this replaced ran the same scripts through both renderers
// and required identical logs, messages and payloads (except the label -> value
// difference on real UUID data); the goldens are that baseline, frozen.
//
// Fed by responses RECORDED from the real backend (tool/record_stac_fixtures.sh); the
// transport is replayed and the live-options answers come from the recorded per-region
// responses with the backend's "region must be a UUID" rule replicated. The same scripts
// run against the real backend in test/live/stac_live_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sdui_demo/services/api_client_impl.dart';
import 'package:sdui_demo/services/api_http_client.dart';
import 'package:sdui_demo/services/api_dtos.dart';
import 'package:sdui_demo/services/auth_token_provider.dart';

import '../../support/fake_api_client.dart';
import '../../support/stac_flow_harness.dart';
import '../../support/stac_fixtures.dart';
import '../../support/stac_scenarios.dart';

Map<String, dynamic> _golden(String name) {
  final all = jsonDecode(File('test/fixtures/golden/scenario_golden.json').readAsStringSync()) as Map<String, dynamic>;
  return (all[name] as Map).cast<String, dynamic>();
}

/// The picked date is "today", which differs run to run; mask it on both sides.
Map<String, dynamic> _snap(ScenarioRun r) => _normalize({
      'log': r.log,
      'notes': r.notes,
      'allValues': r.allValues,
      'completed': r.completed,
    });

Map<String, dynamic> _normalize(Map<String, dynamic> snap) {
  final values = {
    for (final e in (snap['allValues'] as Map).entries)
      e.key as String: (e.key as String).endsWith('.registration_date') ? '<date>' : e.value,
  };
  return {...snap, 'allValues': values};
}

const _stageIds = ['association_details', 'location'];

List<Map<String, dynamic>> _pick(Map<String, dynamic> manifest) {
  final stages = (manifest['stages'] as List).cast<Map<String, dynamic>>();
  return [for (final id in _stageIds) stages.firstWhere((s) => s['stageId'] == id)];
}

/// Rewrites every options list so each option's value equals its label — the
/// only data shape in which the old engine's label-storing dropdown can
/// cascade correctly, used to isolate LOGIC parity from the deliberate
/// label -> value change.
dynamic _labelIsValue(dynamic node) {
  if (node is Map) {
    return <String, dynamic>{
      for (final e in node.entries)
        e.key as String: e.key == 'options' && e.value is List
            ? <dynamic>[
                for (final o in (e.value as List))
                  if (o is Map && o.containsKey('label'))
                    <String, dynamic>{'label': o['label'], 'value': o['label']}
                  else
                    _labelIsValue(o),
              ]
            : _labelIsValue(e.value),
    };
  }
  if (node is List) return <dynamic>[for (final v in node) _labelIsValue(v)];
  return node;
}

FakeApiClient _api({
  required List<Map<String, dynamic>> stac,
  required Map<String, List<FieldOptionDto>> districtsByRegion,
  required bool enforceBackendUuidRule,
}) {
  final options = {
    for (final e in districtsByRegion.entries) FakeApiClient.optionsKey('district', {'region': e.key}): e.value,
  };
  final api = enforceBackendUuidRule
      ? BackendRulesApiClient(optionsByEndpoint: options)
      : FakeApiClient(optionsByEndpoint: options);
  api.stacStages = stac;
  return api;
}

Future<ScenarioRun> _run(
  WidgetTester tester, {
  required List<Map<String, dynamic>> stac,
  required Map<String, List<FieldOptionDto>> districtsByRegion,
  bool enforceBackendUuidRule = true,
}) async {
  final run = ScenarioRun();
  await tester.pumpWidget(stacFlowApp(
    apiClient: _api(stac: stac, districtsByRegion: districtsByRegion, enforceBackendUuidRule: enforceBackendUuidRule),
    stacStages: stac,
    workflowId: 'w',
    clientId: 'c',
    caseId: recordedStacManifest()['case_id'] as String,
  ));
  await tester.pumpAndSettle();
  await associationScenario(tester, run);
  await locationScenario(tester, run);
  return run;
}

/// What the real ApiClientImpl would put on the wire for [values] — the
/// nested body of POST /cases/{id}/submit — captured at the transport level.
Future<Map<String, dynamic>> _submitBody(WidgetTester tester, Map<String, dynamic> values) async {
  late Map<String, dynamic> body;
  final client = ApiClientImpl(
    httpClient: ApiHttpClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'case_id': 'c', 'status': 'submitted', 'record_id': null}), 200);
      }),
    ),
    authTokenProvider: DevAuthTokenProvider(token: 't'),
  );
  await tester.runAsync(() => client.submitCase(caseId: 'c', values: values));
  return body;
}


void main() {
  final stac = _pick(recordedStacManifest());
  final realDistricts = recordedDistrictOptionsByRegionValue();

  group('association_details + location, data where label == value', () {
    testWidgets('matches the golden recorded from the previous renderer: cascade, validation, payload, wire body',
        (tester) async {
      final stacLV = (_labelIsValue(stac) as List).cast<Map<String, dynamic>>();
      final byLabel = <String, List<FieldOptionDto>>{};
      final regionOptions = (((stac[1]['widget'] as Map)['children'] as List).cast<Map<String, dynamic>>())
          .firstWhere((f) => f['id'] == 'region')['options'] as List;
      for (final r in regionOptions.cast<Map<String, dynamic>>()) {
        byLabel[r['label'] as String] = [
          for (final d in realDistricts[r['value']]!) FieldOptionDto(label: d.label, value: d.label),
        ];
      }

      final run = await _run(tester, stac: stacLV, districtsByRegion: byLabel, enforceBackendUuidRule: false);

      expect(_snap(run), _normalize(_golden('association_location_label_equals_value')));
      // and not vacuous:
      expect(run.log, contains('assoc: company_name shown after Group = true'));
      expect(run.log, contains('loc: district options after region = [Bole, Kirkos, Yeka]'));
      expect(run.allValues['location.region'], 'Addis Ababa');
      expect(run.allValues['association_details.company_name'], 'Acme');

      // The exact nested body ApiClientImpl.submitCase puts on the wire.
      final body = await _submitBody(tester, run.allValues);
      expect((body['values'] as Map)['location'], containsPair('district', 'Bole'));
      expect((body['values'] as Map)['association_details'], {'association_type': 'Group', 'company_name': 'Acme'});
    });
  });

  group('location, the REAL data (label != value: real UUID region values)', () {
    testWidgets('the cascade works and the flow completes; matches the golden', (tester) async {
      final run = await _run(tester, stac: stac, districtsByRegion: realDistricts);

      expect(_snap(run), _normalize(_golden('association_location_real_uuid_values')));
      expect(run.log, contains('loc: district failed-to-load shown = false'));
      expect(run.log.last, 'loc: flow completed = true');
      final regionUuid = recordedRegionValue('Addis Ababa');
      expect(run.allValues['location.region'], regionUuid);
      expect(realDistricts[regionUuid]!.map((d) => d.value), contains(run.allValues['location.district']));
      // The required-error wording follows the label as displayed.
      expect(run.notes['requiredMessage:district'], 'district (select a dependency first) is required');
      expect(run.notes['requiredMessage:district:afterRegion'], 'district is required');
    });
  });

  group('hidden fields\' values are dropped at submit', () {
    Future<Map<String, dynamic>> run(WidgetTester tester, Future<void> Function() script) async {
      await tester.pumpWidget(stacFlowApp(
        apiClient: _api(stac: stac, districtsByRegion: realDistricts, enforceBackendUuidRule: true),
        stacStages: [stac[0]],
        workflowId: 'w',
        clientId: 'c',
        caseId: recordedStacManifest()['case_id'] as String,
      ));
      await tester.pumpAndSettle();
      await script();
      final r = ScenarioRun();
      captureResult(tester, r);
      return r.allValues;
    }

    testWidgets('typed, then hidden again: the key is ABSENT from the payload (not blank, not null)', (tester) async {
      final values = await run(tester, () async {
        await choose(tester, 'Group', dropdown: 0);
        await tester.enterText(textFieldWith('company_name'), 'Acme');
        await choose(tester, 'Individual', dropdown: 0);
        expect(isShown('company_name'), isFalse);
        await pressContinue(tester);
      });
      expect(values, {'association_details.association_type': 'Individual'});
      expect(values.containsKey('association_details.company_name'), isFalse);
    });

    testWidgets('REGRESSION: hidden, shown again, still filled: the current value IS submitted', (tester) async {
      final values = await run(tester, () async {
        await choose(tester, 'Group', dropdown: 0);
        await tester.enterText(textFieldWith('company_name'), 'Acme');
        await choose(tester, 'Individual', dropdown: 0);
        await choose(tester, 'Group', dropdown: 0);
        expect(isShown('company_name'), isTrue);
        await tester.enterText(textFieldWith('company_name'), 'Beta Ltd');
        await pressContinue(tester);
      });
      expect(values['association_details.association_type'], 'Group');
      expect(values['association_details.company_name'], 'Beta Ltd');
    });

    testWidgets('REGRESSION: shown, still visible at submit: kept (only CURRENT visibility matters)', (tester) async {
      final values = await run(tester, () async {
        await choose(tester, 'Group', dropdown: 0);
        await tester.enterText(textFieldWith('company_name'), 'Acme');
        await pressContinue(tester);
      });
      expect(values['association_details.company_name'], 'Acme');
    });

    testWidgets('a field that was never shown has no key either', (tester) async {
      final values = await run(tester, () async {
        await choose(tester, 'Individual', dropdown: 0);
        await pressContinue(tester);
      });
      expect(values.keys, ['association_details.association_type']);
    });
  });

  Future<ScenarioRun> stageRun(
    WidgetTester tester,
    String stageId,
    Future<void> Function(WidgetTester, ScenarioRun) scenario,
  ) async {
    final run = ScenarioRun();
    await tester.pumpWidget(stacFlowApp(
      apiClient: _api(
        stac: recordedStacStages([stageId]),
        districtsByRegion: realDistricts,
        enforceBackendUuidRule: true,
      ),
      stacStages: recordedStacStages([stageId]),
      workflowId: 'w',
      clientId: 'c',
      caseId: recordedStacManifest()['case_id'] as String,
    ));
    await tester.pumpAndSettle();
    await scenario(tester, run);
    return run;
  }

  group('text length bounds — real recorded length_rules stage', () {
    testWidgets('exact messages match the golden; unbounded and empty-optional fields unaffected', (tester) async {
      final run = await stageRun(tester, 'length_rules', (t, r) => lengthScenario(t, r));

      expect(_snap(run), _normalize(_golden('length_rules')));
      expect(run.notes['empty:reference_code'], 'reference_code is required');
      expect(run.notes['empty:tin_number'], '(none)', reason: 'optional and empty: no error');
      expect(run.notes['too-short:reference_code'], 'reference_code must be at least 3 characters');
      expect(run.notes['too-short:tin_number'], 'tin_number must be at least 5 characters');
      expect(run.notes['too-long:reference_code'], 'reference_code must be at most 6 characters');
      expect(run.notes['too-long:tin_number'], 'tin_number must be at most 10 characters');
      for (final step in ['empty', 'too-short', 'too-long']) {
        expect(run.notes['$step:notes'], '(none)', reason: 'a field with no bounds is never length-checked');
      }
      expect((run.allValues['length_rules.notes'] as String).length, 300);
    });
  });

  group('Amharic / Unicode and optional-field rules — real recorded unicode_rules stage', () {
    testWidgets('exact messages match the golden; Amharic submitted intact', (tester) async {
      final run = await stageRun(tester, 'unicode_rules', (t, r) => unicodeScenario(t, r));

      expect(_snap(run), _normalize(_golden('unicode_rules')));
      expect(run.notes['empty:am_name'], 'am_name is required');
      expect(run.notes['empty:single_char'], '(none)');
      expect(run.notes['empty:opt_code'], '(none)');
      expect(run.notes['amharic-too-short:am_name'], 'am_name must be at least 2 characters');
      expect(run.notes['amharic-too-long:am_name'], 'am_name must be at most 8 characters');
      expect(run.notes['digits-in-name:am_name'], 'am_name format is invalid');
      expect(run.notes['optional-typed-invalid:single_char'], 'single_char format is invalid');
      expect(run.notes['optional-typed-invalid:opt_code'], 'opt_code format is invalid');
      expect(run.notes['emoji-ok-code-short:single_char'], '(none)');
      expect(run.notes['emoji-ok-code-short:opt_code'], 'opt_code must be at least 3 characters');
      expect(run.allValues['unicode_rules.am_name'], 'አበበ በቀለ');
      expect(run.allValues['unicode_rules.single_char'], '\u{1F600}');
    });
  });
}
