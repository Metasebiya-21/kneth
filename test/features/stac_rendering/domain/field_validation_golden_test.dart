// The text-validation rule against 1,824 results recorded from the previous renderer's
// real form validator while it still existed (test/fixtures/golden/validation_golden.json:
// 19 values incl. Amharic and emoji x required/optional x 8 regexes x 6 bound pairs).
// While both existed a test compared the two implementations live; this is that
// comparison, frozen. The file was recorded (and the Stac rule asserted equal to it at
// recording time) on 2026-09-24, immediately before the old renderer was removed.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/stac_rendering/domain/field_validation.dart';

void main() {
  test('validateTextField reproduces every recorded result of the previous renderer', () {
    final rows = (jsonDecode(File('test/fixtures/golden/validation_golden.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    expect(rows, hasLength(1824));

    final mismatches = <String>[];
    for (final row in rows) {
      final actual = validateTextField(
        label: 'f',
        value: row['value'],
        required: row['required'] as bool,
        regex: row['regex'] as String?,
        minLen: row['minLen'] as int?,
        maxLen: row['maxLen'] as int?,
      );
      if (actual != row['expected']) mismatches.add('$row -> got $actual');
    }
    expect(mismatches, isEmpty);
  });

  test('the golden is not vacuous: it contains every kind of outcome', () {
    final rows = (jsonDecode(File('test/fixtures/golden/validation_golden.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final outcomes = rows.map((r) => r['expected']).toSet();
    expect(outcomes, contains(null));
    expect(outcomes, contains('f is required'));
    expect(outcomes, contains('f format is invalid'));
    expect(outcomes.whereType<String>().any((m) => m.startsWith('f must be at least')), isTrue);
    expect(outcomes.whereType<String>().any((m) => m.startsWith('f must be at most')), isTrue);
  });
}
