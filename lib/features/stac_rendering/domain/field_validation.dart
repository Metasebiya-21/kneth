/// Submit-time validation rules for the Stac-rendered form fields.
///
/// These replicate what the previous renderer's form validator
/// did (read from its source, not guessed from the schema) while both paths
/// existed; the engine was removed at the end of the migration
/// (STAC_MIGRATION_SCOPING.md section 14). For a text field:
///
/// - empty (null or whitespace-only): "<label> is required" if required, and
///   nothing at all if optional. **Nothing else is checked for an empty value.**
/// - non-empty, required *or optional* (unified 2026-09-24; before that the
///   regex was skipped for optional fields while length was not):
///   1. a value that doesn't match the regex is "<label> format is invalid";
///   2. shorter than `minLen` is "<label> must be at least N characters",
///      longer than `maxLen` is "<label> must be at most N characters"
///      (`character` for N = 1).
///   Length is counted in code points, so an emoji is one character.
///
/// Regexes are compiled in Unicode mode first, falling back to Dart's default
/// mode only for a pattern that mode rejects (e.g. `\_`), and a pattern that
/// compiles in neither is treated as matching rather than throwing (the field
/// degrades to "no format check" — [isCompilableRegex] lets the caller make that
/// visible; the text parser reports it once per mount). Unicode
/// mode is what makes `\p{L}` work at all (in the default mode it silently
/// matches nothing) and makes `.`/`{n}` count code points, consistent with the
/// length rule (section 14.1). Note `\w`/`\d` stay ASCII-only in Dart in both
/// modes: an author who wants Ge'ez should use `\p{L}` or a `\u1200-\u137F` range.
///
/// Required-only dropdown/date rules are below. Pure Dart, no I/O, so it lives in
/// domain/ like `FieldConfig.effectiveState`.
String? validateTextField({
  required String label,
  required Object? value,
  required bool required,
  String? regex,
  int? minLen,
  int? maxLen,
}) {
  final text = value?.toString();
  final isEmpty = text == null || text.trim().isEmpty;
  if (isEmpty) return required ? '$label is required' : null;

  if (regex != null && !_matches(regex, text)) return '$label format is invalid';

  final length = text.runes.length;
  if (minLen != null && length < minLen) {
    return '$label must be at least $minLen ${minLen == 1 ? 'character' : 'characters'}';
  }
  if (maxLen != null && length > maxLen) {
    return '$label must be at most $maxLen ${maxLen == 1 ? 'character' : 'characters'}';
  }
  return null;
}

/// Required-only validation, shared by dropdowns (whitespace-only counts as
/// empty, [trim] true) and dates (only null/'' counts, [trim] false),
/// matching the two slightly different emptiness checks the engine uses.
String? validateRequiredValue({
  required String label,
  required Object? value,
  required bool required,
  required bool trim,
}) {
  if (!required) return null;
  final text = value?.toString();
  final isEmpty = text == null || (trim ? text.trim().isEmpty : text.isEmpty);
  return isEmpty ? '$label is required' : null;
}

/// Compiles [pattern] the way validation does: Unicode mode first, then
/// Dart's default mode, or null when neither accepts it.
RegExp? _compile(String pattern) {
  try {
    return RegExp(pattern, unicode: true);
  } on FormatException {
    try {
      return RegExp(pattern);
    } on FormatException {
      return null;
    }
  }
}

/// Whether [pattern] compiles in either mode. When it doesn't, [validateTextField]
/// silently skips the format check for that field, so callers use this to
/// surface the problem (a pattern valid for the backend's Python `re` can be
/// invalid for Dart, e.g. `(?P<name>...)` or inline flags like `(?i)`).
bool isCompilableRegex(String pattern) => _compile(pattern) != null;

bool _matches(String pattern, String value) {
  final compiled = _compile(pattern);
  // uncompilable in either mode: can't be checked against
  return compiled == null ? true : compiled.hasMatch(value);
}
