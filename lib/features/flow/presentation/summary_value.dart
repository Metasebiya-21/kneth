import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/display_value.dart';
import '../domain/dynamic_options.dart';
import '../domain/field_config.dart';
import '../domain/flow_case_state.dart';
import 'flow_notifier.dart';
import 'resolved_options_cache.dart';

/// Options for a live DYNAMIC field that no screen has cached (the case was
/// resumed after a restart): re-fetched from the same route the stage used,
/// with the dependency values read from what was collected for that stage.
/// Null when they can't be determined. Failures are swallowed into null by
/// the caller — the summary falls back to the raw value.
final _summaryOptionsProvider = FutureProvider.family<List<FieldOption>?, (String, String)>((ref, key) async {
  final (stageId, fieldKey) = key;
  final state = ref.read(flowNotifierProvider);
  if (state is! FlowViewReady) return null;
  final caseState = state.caseState;
  final field = fieldFor(caseState, stageId, fieldKey);
  if (field == null) return null;
  final dependencies = resolveDependencyValues(field.property.dependsOn, caseState.collectedValues[stageId] ?? const {});
  if (dependencies == null) return null;
  final dtos = await ref.read(apiClientProvider).fetchOptions(
        clientId: caseState.manifest.clientId,
        workflowId: caseState.manifest.workflowId,
        fieldKey: fieldKey,
        dependencyValues: dependencies,
      );
  final options = [for (final o in dtos) FieldOption(label: o.label, value: o.value)];
  ref.read(resolvedOptionsProvider.notifier).record(stageId, fieldKey, options);
  return options;
});

/// The field a flat payload key (`stageId.fieldKey`) refers to, if any.
FieldConfig? fieldFor(FlowCaseState caseState, String stageId, String fieldKey) {
  for (final stage in caseState.manifest.stages) {
    if (stage.stageId != stageId) continue;
    for (final field in stage.fields) {
      if (field.key == fieldKey) return field;
    }
  }
  return null;
}

/// One value on the completion summary. For a select field it shows the
/// option's human-readable label rather than its stored value, looking in
/// (1) the field's own static/eager options in the manifest, (2) options a
/// stage screen already fetched ([resolvedOptionsProvider]), and only then
/// (3) re-fetching — the rare case of a resumed case with an empty cache.
/// Anything unresolvable shows the raw stored value ([displayLabelFor]).
/// Everything that isn't a select field (text, dates, file paths) is shown
/// exactly as before.
class SummaryValueText extends ConsumerWidget {
  final FlowCaseState caseState;
  final String payloadKey;
  final Object? value;

  const SummaryValueText({super.key, required this.caseState, required this.payloadKey, required this.value});

  static Widget _text(String text) => Text(text, textAlign: TextAlign.end);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dot = payloadKey.indexOf('.');
    if (dot == -1) return _text('$value');
    final stageId = payloadKey.substring(0, dot);
    final fieldKey = payloadKey.substring(dot + 1);
    final field = fieldFor(caseState, stageId, fieldKey);
    if (field == null || field.type != FieldType.select || value == null) return _text('$value');

    final staticOptions = field.property.options;
    if (staticOptions != null && staticOptions.isNotEmpty) return _text(displayLabelFor(value, staticOptions));

    final cached = ref.watch(resolvedOptionsProvider)['$stageId.$fieldKey'];
    if (cached != null) return _text(displayLabelFor(value, cached));

    if (field.inputMode != FieldInputMode.dynamic_) return _text('$value');
    return ref.watch(_summaryOptionsProvider((stageId, fieldKey))).when(
          data: (options) => _text(displayLabelFor(value, options)),
          loading: () => _text('$value'),
          error: (_, __) => _text('$value'),
        );
  }
}
