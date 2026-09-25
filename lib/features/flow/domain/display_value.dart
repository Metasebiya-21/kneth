import 'field_config.dart';

/// The text to show for a stored field [value]: the label of the option whose
/// real `value` equals it, or the raw value when there is no such option (no
/// options known, or none matches — including a label stored by an older
/// build). The fallback is deliberately the raw stored value, never a
/// blank or an error: a summary should degrade, not fail. Pure, no I/O.
///
/// Exists because the Stac dropdown stores an option's real value (a UUID for
/// reference-data fields) rather than its label; anything that *displays*
/// what was collected needs to map it back (STAC_MIGRATION_SCOPING.md 12.4,
/// item closed 2026-09-24).
String displayLabelFor(Object? value, List<FieldOption>? options) {
  final raw = '$value';
  if (options == null) return raw;
  for (final option in options) {
    if (option.value == raw) return option.label;
  }
  return raw;
}
