import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stac_test_actions.dart';
import 'stac_test_harness.dart';

Map<String, dynamic> _column(List<Map<String, dynamic>> children) => {'type': 'column', 'children': children};

void main() {
  group('kneth_text', () {
    testWidgets('renders the label, writes every keystroke, and restores a seeded value', (tester) async {
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(
        widgetJson: _column([
          {'type': 'kneth_text', 'id': 'full_name', 'label': 'Full name', 'required': false},
        ]),
        submitted: submitted,
        initialValues: {'full_name': 'Ada'},
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Ada'), findsOneWidget);
      await tester.enterText(textFieldLabelled('Full name'), 'Ada L');
      await tapContinue(tester);
      expect(submitted.single, {'full_name': 'Ada L'});
    });

    testWidgets('required + regex: invalid format then required, exactly as the old engine words them', (tester) async {
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(
        widgetJson: _column([
          {'type': 'kneth_text', 'id': 'postal_code', 'label': 'postal_code', 'required': true, 'regex': r'^[0-9]{4}$'},
        ]),
        submitted: submitted,
      ));
      await tester.pumpAndSettle();

      await tapContinue(tester);
      expect(find.text('postal_code is required'), findsOneWidget);

      await tester.enterText(textFieldLabelled('postal_code'), '12a4');
      await tapContinue(tester);
      expect(find.text('postal_code format is invalid'), findsOneWidget);
      expect(submitted, isEmpty);

      await tester.enterText(textFieldLabelled('postal_code'), '1234');
      await tapContinue(tester);
      expect(find.textContaining('postal_code'), findsWidgets); // label only
      expect(find.text('postal_code format is invalid'), findsNothing);
      expect(submitted.single, {'postal_code': '1234'});
    });

    group('an uncompilable regex', () {
      const badPattern = '(?P<year>[0-9]{4})'; // valid Python `re`, invalid Dart

      Future<void> pumpField(WidgetTester tester, List<Map<String, dynamic>> submitted, {String? regex, bool required = false}) async {
        await tester.pumpWidget(stacStageApp(
          widgetJson: _column([
            {'type': 'kneth_text', 'id': 'year', 'label': 'Year', 'required': required, 'regex': regex},
          ]),
          submitted: submitted,
        ));
        await tester.pumpAndSettle();
      }

      /// Collects what [body] reports through FlutterError.onError, restoring the
      /// handler in a finally so a failing expectation can't leave it replaced
      /// (flutter_test hangs on that).
      Future<List<FlutterErrorDetails>> captureReports(Future<void> Function() body) async {
        final reports = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = reports.add;
        try {
          await body();
        } finally {
          FlutterError.onError = previous;
        }
        return reports;
      }

      testWidgets('reports a FlutterError naming the field key and the pattern, once per mount', (tester) async {
        final reports = await captureReports(() => pumpField(tester, [], regex: badPattern));

        expect(reports, hasLength(1));
        final text = '${reports.single.exceptionAsString()} ${reports.single.context}';
        expect(text, contains('year'));
        expect(text, contains(badPattern));
        expect(reports.single.library, 'kneth_text');
      });

      testWidgets('the field still degrades gracefully: accepts input, no format error, submits', (tester) async {
        final submitted = <Map<String, dynamic>>[];
        final reports = await captureReports(() async {
          await pumpField(tester, submitted, regex: badPattern, required: true);
          await tapContinue(tester);
          expect(find.text('Year is required'), findsOneWidget); // required still enforced

          await tester.enterText(textFieldLabelled('Year'), 'anything at all');
          await tapContinue(tester);
        });
        expect(reports, hasLength(1)); // still reported, and nothing else was thrown
        expect(find.text('Year format is invalid'), findsNothing);
        expect(submitted.single, {'year': 'anything at all'});
        expect(tester.takeException(), isNull);
      });

      testWidgets('a compilable regex, or none, reports nothing', (tester) async {
        final reports = await captureReports(() async {
          await pumpField(tester, [], regex: r'^[0-9]{4}$');
          await pumpField(tester, [], regex: null);
        });
        expect(reports, isEmpty);
      });
    });

    testWidgets('editing a field clears that field\'s error', (tester) async {
      await tester.pumpWidget(stacStageApp(
        widgetJson: _column([
          {'type': 'kneth_text', 'id': 'n', 'label': 'n', 'required': true},
        ]),
        submitted: [],
      ));
      await tester.pumpAndSettle();
      await tapContinue(tester);
      expect(find.text('n is required'), findsOneWidget);

      await tester.enterText(textFieldLabelled('n'), 'x');
      await tester.pump();
      expect(find.text('n is required'), findsNothing);
    });

    testWidgets('an optional field: empty is fine; once typed it is validated like a required one (Phase 2)',
        (tester) async {
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(
        widgetJson: _column([
          {'type': 'kneth_text', 'id': 'n', 'label': 'n', 'required': false, 'regex': r'^\d+$'},
        ]),
        submitted: submitted,
      ));
      await tester.pumpAndSettle();

      await tapContinue(tester); // empty: no error of any kind
      expect(submitted.single, isEmpty);
      submitted.clear();

      await tester.enterText(textFieldLabelled('n'), 'not digits');
      await tapContinue(tester);
      expect(find.text('n format is invalid'), findsOneWidget);
      expect(submitted, isEmpty);

      await tester.enterText(textFieldLabelled('n'), '123');
      await tapContinue(tester);
      expect(submitted.single, {'n': '123'});
    });

    testWidgets('Amharic text is entered, kept exactly, and submitted (and validated per character)', (tester) async {
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(
        widgetJson: _column([
          {'type': 'kneth_text', 'id': 'name', 'label': 'name', 'required': true, 'minLen': 3, 'maxLen': 7},
        ]),
        submitted: submitted,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(textFieldLabelled('name'), 'አበ');
      await tapContinue(tester);
      expect(find.text('name must be at least 3 characters'), findsOneWidget);

      await tester.enterText(textFieldLabelled('name'), 'አበበ በቀለ ኃይሌ');
      await tapContinue(tester);
      expect(find.text('name must be at most 7 characters'), findsOneWidget);

      await tester.enterText(textFieldLabelled('name'), 'አበበ በቀለ');
      await tapContinue(tester);
      expect(submitted.single, {'name': 'አበበ በቀለ'});
      expect(submitted.single['name'].toString().codeUnits, 'አበበ በቀለ'.codeUnits);
    });

    group('minLen/maxLen (item 2)', () {
      Future<List<Map<String, dynamic>>> pump(WidgetTester tester, {bool required = true, int? min, int? max}) async {
        final submitted = <Map<String, dynamic>>[];
        await tester.pumpWidget(stacStageApp(
          widgetJson: _column([
            {'type': 'kneth_text', 'id': 'n', 'label': 'n', 'required': required, if (min != null) 'minLen': min, if (max != null) 'maxLen': max},
          ]),
          submitted: submitted,
        ));
        await tester.pumpAndSettle();
        return submitted;
      }

      testWidgets('too short fails, too long fails, in range passes', (tester) async {
        final submitted = await pump(tester, min: 3, max: 6);

        await tester.enterText(textFieldLabelled('n'), 'ab');
        await tapContinue(tester);
        expect(find.text('n must be at least 3 characters'), findsOneWidget);

        await tester.enterText(textFieldLabelled('n'), 'abcdefg');
        await tapContinue(tester);
        expect(find.text('n must be at most 6 characters'), findsOneWidget);
        expect(submitted, isEmpty);

        await tester.enterText(textFieldLabelled('n'), 'abcd');
        await tapContinue(tester);
        expect(submitted.single, {'n': 'abcd'});
      });

      testWidgets('applies to an optional field once typed; an empty optional field passes', (tester) async {
        final submitted = await pump(tester, required: false, min: 3);
        await tester.enterText(textFieldLabelled('n'), 'ab');
        await tapContinue(tester);
        expect(find.text('n must be at least 3 characters'), findsOneWidget);

        await tester.enterText(textFieldLabelled('n'), '');
        await tapContinue(tester);
        expect(submitted.single, {'n': ''});
      });

      testWidgets('no bounds on the field: completely unaffected (any length submits)', (tester) async {
        final submitted = await pump(tester);
        await tester.enterText(textFieldLabelled('n'), 'x' * 400);
        await tapContinue(tester);
        expect(submitted.single['n'], hasLength(400));
      });
    });

    testWidgets('a "{{...}}" in backend text survives Stac variable substitution (the registry is never populated)',
        (tester) async {
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(
        widgetJson: _column([
          {'type': 'kneth_text', 'id': 'n', 'label': 'n {{x}}', 'required': true, 'regex': r'^a{{2}}$'},
        ]),
        submitted: submitted,
      ));
      await tester.pumpAndSettle();
      expect(textFieldLabelled('n {{x}}'), findsOneWidget);
    });
  });

  group('kneth_date', () {
    testWidgets('shows "Select Date", required error, then stores the picked date as an ISO string', (tester) async {
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(
        widgetJson: _column([
          {'type': 'kneth_date', 'id': 'registration_date', 'label': 'registration_date', 'required': true},
        ]),
        submitted: submitted,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Select Date'), findsOneWidget);

      await tapContinue(tester);
      expect(find.text('registration_date is required'), findsOneWidget);

      await tester.tap(find.text('Select Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tapContinue(tester);
      expect(submitted, hasLength(1));
      final stored = submitted.single['registration_date'] as String;
      expect(DateTime.tryParse(stored), isNotNull);
      expect(stored, contains('T'), reason: 'toIso8601String(), as the old widget stores it');
      expect(find.text(stored.split('T').first), findsOneWidget);
    });

    testWidgets('a non-required date can be left empty', (tester) async {
      final submitted = <Map<String, dynamic>>[];
      await tester.pumpWidget(stacStageApp(
        widgetJson: _column([
          {'type': 'kneth_date', 'id': 'd', 'label': 'd', 'required': false},
        ]),
        submitted: submitted,
      ));
      await tester.pumpAndSettle();
      await tapContinue(tester);
      expect(submitted.single, isEmpty);
    });
  });
}
