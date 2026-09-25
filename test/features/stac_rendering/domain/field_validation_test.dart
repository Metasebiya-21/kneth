// These rules replicate the removed renderer's form validator (see field_validation_golden_test.dart)
// exactly (read from its source) — each case below is one branch of it.
import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/stac_rendering/domain/field_validation.dart';

void main() {
  group('validateTextField', () {
    test('an optional field that is EMPTY has no error of any kind (regex and bounds included)', () {
      for (final empty in [null, '', '   ']) {
        expect(validateTextField(label: 'Zip', value: empty, required: false, regex: r'^\d{4}$', minLen: 4, maxLen: 4), isNull);
      }
    });

    test('an optional field, once typed, is validated exactly like a required one (Phase 2)', () {
      for (final required in [true, false]) {
        expect(validateTextField(label: 'Zip', value: 'abc', required: required, regex: r'^\d{4}$'), 'Zip format is invalid');
        expect(validateTextField(label: 'Zip', value: '12', required: required, minLen: 4), 'Zip must be at least 4 characters');
        expect(validateTextField(label: 'Zip', value: '1234', required: required, regex: r'^\d{4}$', minLen: 4), isNull);
      }
    });

    test('required: null and whitespace-only are "is required"', () {
      expect(validateTextField(label: 'Zip', value: null, required: true), 'Zip is required');
      expect(validateTextField(label: 'Zip', value: '   ', required: true), 'Zip is required');
    });

    test('required + regex: a non-matching value is "format is invalid"', () {
      expect(validateTextField(label: 'Zip', value: '12a4', required: true, regex: r'^\d{4}$'), 'Zip format is invalid');
      expect(validateTextField(label: 'Zip', value: '1234', required: true, regex: r'^\d{4}$'), isNull);
    });

    test('an empty value with a regex is "required", not "invalid"', () {
      expect(validateTextField(label: 'Zip', value: '', required: true, regex: r'^\d{4}$'), 'Zip is required');
    });

    test('a malformed backend pattern is treated as matching instead of throwing', () {
      expect(validateTextField(label: 'X', value: 'v', required: true, regex: '(unclosed'), isNull);
    });
  });

  group('isCompilableRegex', () {
    test('true for patterns either mode accepts, false only when neither does', () {
      expect(isCompilableRegex(r'^\d{4}$'), isTrue);
      expect(isCompilableRegex(r'^\p{L}+$'), isTrue); // unicode mode
      expect(isCompilableRegex(r'^\_$'), isTrue); // rejected by unicode mode, fine in default
      expect(isCompilableRegex('(unclosed'), isFalse);
      // Valid for the backend's Python `re`, not for Dart:
      expect(isCompilableRegex(r'(?P<year>\d{4})'), isFalse);
      expect(isCompilableRegex(r'(?i)abc'), isFalse);
    });
  });

  group('validateRequiredValue', () {
    test('not required is never an error', () {
      expect(validateRequiredValue(label: 'D', value: null, required: false, trim: true), isNull);
    });

    test('dropdown emptiness trims; date emptiness does not', () {
      expect(validateRequiredValue(label: 'D', value: '  ', required: true, trim: true), 'D is required');
      expect(validateRequiredValue(label: 'D', value: '  ', required: true, trim: false), isNull);
      expect(validateRequiredValue(label: 'D', value: '', required: true, trim: false), 'D is required');
      expect(validateRequiredValue(label: 'D', value: null, required: true, trim: false), 'D is required');
    });
  });

  group('validateTextField length bounds (item 2)', () {
    String? v(String? value, {bool required = false, int? min, int? max, String? regex}) => validateTextField(
          label: 'code',
          value: value,
          required: required,
          minLen: min,
          maxLen: max,
          regex: regex,
        );

    test('too short fails, too long fails, in range (inclusive) passes', () {
      expect(v('ab', min: 3, max: 6), 'code must be at least 3 characters');
      expect(v('abcdefg', min: 3, max: 6), 'code must be at most 6 characters');
      expect(v('abc', min: 3, max: 6), isNull);
      expect(v('abcdef', min: 3, max: 6), isNull);
    });

    test('singular wording for a bound of 1', () {
      expect(v('', required: true, min: 1), 'code is required');
      expect(v('ab', max: 1), 'code must be at most 1 character');
      expect(validateTextField(label: 'code', value: 'a', required: false, minLen: 2), 'code must be at least 2 characters');
    });

    test('applies to an OPTIONAL field once something is typed, but never to an empty value', () {
      expect(v('ab', min: 3), 'code must be at least 3 characters');
      expect(v('', min: 3), isNull);
      expect(v(null, min: 3), isNull);
      expect(v('   ', min: 3), isNull, reason: 'whitespace-only is empty');
    });

    test('a required empty value is "is required", not a length message', () {
      expect(v('', required: true, min: 3), 'code is required');
    });

    test('regex is checked before length, for required and optional fields alike', () {
      for (final required in [true, false]) {
        expect(v('ab', required: required, min: 3, regex: r'^\d+$'), 'code format is invalid');
        expect(v('12', required: required, min: 3, regex: r'^\d+$'), 'code must be at least 3 characters');
      }
    });

    test('with no bounds set, nothing changes: any length passes', () {
      expect(v('x' * 5000), isNull);
      expect(v('x' * 5000, required: true), isNull);
    });

    test('length counts characters (code points), not UTF-16 units', () {
      expect(v('\u{1F600}\u{1F600}\u{1F600}', max: 3), isNull);
      expect(v('\u{1F600}\u{1F600}\u{1F600}', max: 2), 'code must be at most 2 characters');
    });
  });

  group('Amharic / Unicode (STAC_MIGRATION_SCOPING.md section 14)', () {
    const amharicName = 'አበበ በቀለ'; // 7 code points, all BMP
    const nameRegex = r"^[\p{L}\p{M}\s/'.-]{1,64}$";

    test('a Ge\'ez value is counted per character, and the min/max boundaries are exact', () {
      String? v(String value, {int? min, int? max}) =>
          validateTextField(label: 'name', value: value, required: true, minLen: min, maxLen: max);
      expect('አበበ'.length, 3);
      expect(v('አበ', min: 3), 'name must be at least 3 characters');
      expect(v('አበበ', min: 3, max: 3), isNull);
      expect(v('አበበሰ', max: 3), 'name must be at most 3 characters');
      expect(v(amharicName, min: 7, max: 7), isNull);
    });

    test('the Ge\'ez wordspace (U+1361) is a character, not whitespace: a value made of it is not "empty"', () {
      expect(validateTextField(label: 'n', value: '\u1361', required: true), isNull);
    });

    test('the OLD demo pattern rejected Amharic; a Unicode-aware one accepts it', () {
      expect(validateTextField(label: 'n', value: amharicName, required: true, regex: r'^[a-zA-Z\s/]{1,64}$'),
          'n format is invalid');
      expect(validateTextField(label: 'n', value: amharicName, required: true, regex: nameRegex), isNull);
      expect(validateTextField(label: 'n', value: 'Ada Lovelace', required: true, regex: nameRegex), isNull);
      expect(validateTextField(label: 'n', value: 'abc123', required: true, regex: nameRegex), 'n format is invalid');
    });

    test(r'\p{L} works (in the default Dart mode it silently matches nothing) and a BMP range works too', () {
      expect(validateTextField(label: 'n', value: 'አበበ', required: true, regex: r'^\p{L}+$'), isNull);
      expect(validateTextField(label: 'n', value: 'አበበ', required: true, regex: '^[\u1200-\u137F]+\$'), isNull);
    });

    test('regex quantifiers count code points like the length rule: an emoji is ONE character', () {
      const emoji = '\u{1F600}';
      expect(validateTextField(label: 'n', value: emoji, required: true, regex: r'^.$'), isNull);
      expect(validateTextField(label: 'n', value: emoji, required: true, regex: r'^.{2}$'), 'n format is invalid');
      expect(validateTextField(label: 'n', value: '$emoji$emoji', required: true, regex: r'^.$'), 'n format is invalid');
    });

    test('a pattern only the default mode accepts still works (fallback), and an uncompilable one is treated as matching',
        () {
      expect(validateTextField(label: 'n', value: 'a_b', required: true, regex: r'^a\_b$'), isNull);
      expect(validateTextField(label: 'n', value: 'a_c', required: true, regex: r'^a\_b$'), 'n format is invalid');
      expect(validateTextField(label: 'n', value: 'x', required: true, regex: '(unclosed'), isNull);
    });
  });
}
