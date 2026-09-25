// The scripted interactions the Stac flow is put through. Every step logs what
// it observes so runs can be compared observation by observation (against the
// goldens in test/fixtures/golden/).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stac_flow_harness.dart';

/// association_details: `company_name` is conditional on
/// `association_type == "Group"` (required when shown).
Future<void> associationScenario(WidgetTester tester, ScenarioRun run, {InFlightCountingApiClient? live}) async {
  void log(String s) => run.log.add('assoc: $s');

  log('company_name shown initially = ${isShown('company_name')}');

  await choose(tester, 'Group', dropdown: 0, live: live);
  log('company_name shown after Group = ${isShown('company_name')}');

  await pressContinue(tester, live: live);
  log('"company_name is required" shown = ${hasText('company_name is required')}');
  log('still on the stage = ${hasText('association_type') || isShown('company_name')}');

  await tester.enterText(textFieldWith('company_name'), 'Acme');
  await tester.pump();
  log('required error cleared by typing = ${!hasText('company_name is required')}');

  await choose(tester, 'Individual', dropdown: 0, live: live);
  log('company_name shown after Individual = ${isShown('company_name')}');

  await choose(tester, 'Group', dropdown: 0, live: live);
  log('company_name shown again after Group = ${isShown('company_name')}');
  log('typed text restored on re-show = ${find.widgetWithText(TextField, 'Acme').evaluate().isNotEmpty}');

  await pressContinue(tester, live: live);
  log('advanced past the stage = ${!isShown('company_name') && !hasText('association_type')}');
}

/// location: `region` (eager options), `district` (live, cascades from
/// region), `postal_code` (required, regex `^[0-9]{4}$`), `registration_date`.
/// [pickDistrict] is the label to select if it is on offer.
Future<void> locationScenario(
  WidgetTester tester,
  ScenarioRun run, {
  InFlightCountingApiClient? live,
  String regionLabel = 'Addis Ababa',
  String pickDistrict = 'Bole',
}) async {
  void log(String s) => run.log.add('loc: $s');

  log('district not-ready label shown = ${hasText('district (select a dependency first)')}');

  await pressContinue(tester, live: live);
  for (final f in ['region', 'district', 'postal_code']) {
    final message = textMatching(RegExp('^$f.* is required\$'));
    log('a "$f ... is required" error shown = ${message != null}');
    // Exact wording is a known, documented difference for the DYNAMIC
    // dropdown (the old engine leaks its status suffix into the message), so
    // it's recorded here but kept out of the strict comparison.
    if (message != null) run.notes['requiredMessage:$f'] = message;
  }

  await choose(tester, regionLabel, dropdown: 0, live: live);
  log('district failed-to-load shown = ${hasText('district (failed to load)')}');
  final districts = await optionsOf(tester, dropdown: 1);
  log('district options after region = $districts');

  // The required-error wording again, now that the field is past "not ready"
  // (ready on the Stac path; ready or failed on the old path, depending on
  // the data). Exact text is compared by the tests, not logged here.
  await pressContinue(tester, live: live);
  run.notes['requiredMessage:district:afterRegion'] = textMatching(RegExp(r'^district.* is required$')) ?? '';

  if (districts.contains(pickDistrict)) {
    await choose(tester, pickDistrict, dropdown: 1, live: live);
  }

  await tester.enterText(textFieldWith('postal_code'), '12a4');
  await pressContinue(tester, live: live);
  log('"postal_code format is invalid" shown = ${hasText('postal_code format is invalid')}');

  await tester.enterText(textFieldWith('postal_code'), '1000');
  await tester.pump();
  await tester.tap(find.text('Select Date'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  await pressContinue(tester, live: live);
  captureResult(tester, run);
  log('flow completed = ${run.completed}');
}

/// length_rules: `reference_code` (required, 3..6), `tin_number` (optional,
/// 5..10), `notes` (optional, NO bounds). The exact validation messages go
/// into [ScenarioRun.notes] so the tests can compare them character for
/// character against the goldens.
Future<void> lengthScenario(WidgetTester tester, ScenarioRun run, {InFlightCountingApiClient? live}) async {
  void log(String s) => run.log.add('len: $s');
  String? msg(String field) => textMatching(RegExp('^$field .*(is required|must be at (least|most) .*|format is invalid)\$'));

  Future<void> submitAndRecord(String step) async {
    await pressContinue(tester, live: live);
    for (final f in ['reference_code', 'tin_number', 'notes']) {
      run.notes['$step:$f'] = msg(f) ?? '(none)';
      log('$step $f -> ${run.notes['$step:$f']}');
    }
  }

  await submitAndRecord('empty');

  await tester.enterText(textFieldWith('reference_code'), 'ab'); // 2 < 3
  await tester.enterText(textFieldWith('tin_number'), 'abcd'); // 4 < 5
  await submitAndRecord('too-short');

  await tester.enterText(textFieldWith('reference_code'), 'abcdefg'); // 7 > 6
  await tester.enterText(textFieldWith('tin_number'), 'abcdefghijk'); // 11 > 10
  await submitAndRecord('too-long');

  await tester.enterText(textFieldWith('reference_code'), 'abcd'); // in range
  await tester.enterText(textFieldWith('tin_number'), ''); // optional + empty: fine
  await tester.enterText(textFieldWith('notes'), 'n' * 300); // no bounds: unaffected
  await pressContinue(tester, live: live);
  captureResult(tester, run);
  log('in range advanced = ${run.allValues.containsKey('length_rules.reference_code')}');
}

/// unicode_rules: `am_name` (required, Unicode-letter regex, 2..8 chars),
/// `single_char` (optional, regex `^.$` = exactly one code point) and
/// `opt_code` (optional, regex `^[0-9]+$` AND min length 3). Exact messages go
/// into [ScenarioRun.notes] for character-for-character comparison.
Future<void> unicodeScenario(WidgetTester tester, ScenarioRun run, {InFlightCountingApiClient? live}) async {
  void log(String s) => run.log.add('uni: $s');
  String? msg(String field) => textMatching(RegExp('^$field .*(is required|must be at (least|most) .*|format is invalid)\$'));

  Future<void> submitAndRecord(String step) async {
    await pressContinue(tester, live: live);
    for (final f in ['am_name', 'single_char', 'opt_code']) {
      run.notes['$step:$f'] = msg(f) ?? '(none)';
      log('$step $f -> ${run.notes['$step:$f']}');
    }
  }

  // Phase 2: optional fields that are empty produce no error of any kind.
  await submitAndRecord('empty');

  await tester.enterText(textFieldWith('am_name'), 'አ'); // 1 < min 2
  await submitAndRecord('amharic-too-short');

  await tester.enterText(textFieldWith('am_name'), 'አበበ በቀለ ኃይሌ'); // 12 > max 8
  await submitAndRecord('amharic-too-long');

  await tester.enterText(textFieldWith('am_name'), 'abc123'); // digits fail the \p{L} class
  await submitAndRecord('digits-in-name');

  await tester.enterText(textFieldWith('am_name'), 'አበበ በቀለ'); // exactly 7: valid Amharic
  // Phase 2: OPTIONAL fields, once typed, are validated like required ones.
  await tester.enterText(textFieldWith('single_char'), 'ab'); // regex ^.$ fails
  await tester.enterText(textFieldWith('opt_code'), 'ab'); // regex ^[0-9]+$ fails
  await submitAndRecord('optional-typed-invalid');

  await tester.enterText(textFieldWith('single_char'), '\u{1F600}'); // ONE code point: passes
  await tester.enterText(textFieldWith('opt_code'), '12'); // regex ok, length 2 < 3
  await submitAndRecord('emoji-ok-code-short');

  await tester.enterText(textFieldWith('opt_code'), '123');
  await pressContinue(tester, live: live);
  captureResult(tester, run);
  log('completed = ${run.completed}');
}
