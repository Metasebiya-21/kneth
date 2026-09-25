import 'dart:convert';
import 'dart:io';

import 'package:sdui_demo/services/api_dtos.dart';

/// Real responses recorded from the running backend by
/// `tool/record_stac_fixtures.sh` — same case, both routes. Synchronous
/// reads so they work inside a `testWidgets` body's fake-async zone.
Map<String, dynamic> _read(String name) =>
    jsonDecode(File('test/fixtures/stac/$name').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> recordedStacManifest() => _read('manifest_stac.json');
/// The legacy route's response, recorded 2026-09-24 and FROZEN: kept only as the reference the
/// Stac -> flow-stage mapper is checked against (stac_manifest_mapper_test.dart). The app no longer
/// calls that route and tool/record_stac_fixtures.sh no longer re-records it.
Map<String, dynamic> recordedLegacyManifest() => _read('manifest_legacy.json');

/// Recorded Stac stages by id, in the order given (not manifest order).
List<Map<String, dynamic>> recordedStacStages(List<String> ids) {
  final all = (recordedStacManifest()['stages'] as List).cast<Map<String, dynamic>>();
  return [for (final id in ids) all.firstWhere((s) => s['stageId'] == id)];
}

/// `{regionValue: [{label, value}, ...]}` — the real live-options responses
/// for `district`, one per seeded region.
Map<String, List<FieldOptionDto>> recordedDistrictOptionsByRegionValue() {
  final raw = _read('district_options_by_region_value.json');
  return {
    for (final entry in raw.entries)
      entry.key: [
        for (final o in (entry.value as List).cast<Map<String, dynamic>>())
          FieldOptionDto(label: o['label'] as String, value: o['value'] as String),
      ],
  };
}

Map<String, dynamic> recordedStacStage(String stageId) {
  final stages = (recordedStacManifest()['stages'] as List).cast<Map<String, dynamic>>();
  return stages.firstWhere((s) => s['stageId'] == stageId);
}

Map<String, dynamic> recordedStacWidget(String stageId) =>
    (recordedStacStage(stageId)['widget'] as Map).cast<String, dynamic>();

/// The seeded region option whose label is [label] — its real UUID value.
String recordedRegionValue(String label) {
  final region = _findField(recordedStacWidget('location'), 'region')!;
  return ((region['options'] as List).cast<Map<String, dynamic>>())
      .firstWhere((o) => o['label'] == label)['value'] as String;
}

Map<String, dynamic>? _findField(dynamic node, String id) {
  if (node is Map) {
    if (node['id'] == id && (node['type'] as String? ?? '').startsWith('kneth_')) {
      return node.cast<String, dynamic>();
    }
    for (final v in node.values) {
      final r = _findField(v, id);
      if (r != null) return r;
    }
  } else if (node is List) {
    for (final v in node) {
      final r = _findField(v, id);
      if (r != null) return r;
    }
  }
  return null;
}
