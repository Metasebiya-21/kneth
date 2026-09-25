import 'package:flutter/material.dart';
import 'package:stac/stac.dart';

import '../../../../services/app_exception.dart';
import '../../../../widgets/app_error_view.dart';
import '../../../flow/domain/field_config.dart';
import '../../../flow/domain/stage_config.dart';
import '../../../flow/presentation/dynamic_options_controller.dart';
import '../../domain/field_validation.dart';
import '../knet_stac_scope.dart';
import '../stac_form_values.dart';

/// `kneth_dropdown` — static ENUM, eager-resolved DYNAMIC (indistinguishable
/// from a static enum by the time it reaches the client, per section 11.3),
/// and live/deferred DYNAMIC (`dynamicConfig` + `dependsOn`, no `options`).
/// The built-in `dropdownMenu` can't be a form field (2.5), so this is the
/// whole widget.
///
/// **Live options reuse the real [DynamicOptionsController]**, not a copy of
/// it: one controller per dynamic dropdown, built over a one-field
/// [StageConfig]. Its `sync` (readiness, dependency-change detection via
/// `changedDynamicFieldKeys`, fetch via `ApiClient.fetchOptions`) and `retry`
/// are called as-is, and the field it reports as "cleared" is cleared here —
/// so cascade/clear-on-change logic exists once. Failure renders through the
/// shared [AppErrorView] with its retry, above the field, as the old screen
/// does.
///
/// **Stores the option's real `value`, not its label.** The previous renderer's
/// dropdown could only store the label (a plugin constraint that doesn't
/// apply to a widget we own). That mattered in practice: the backend's live
/// options route requires the dependency value to be the parent option's
/// real value (`region` must be a UUID, `dynamic_options_adapter.py`), so the
/// label-storing path cannot cascade against real reference data. See
/// STAC_MIGRATION_SCOPING.md section 12 for the consumer-by-consumer check.
class KnethDropdownParser extends StacParser<Map<String, dynamic>> {
  const KnethDropdownParser();

  @override
  String get type => 'kneth_dropdown';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) =>
      _KnethDropdown(model, key: ValueKey('kneth_dropdown:${model['id']}'));
}

class _KnethDropdown extends StatefulWidget {
  final Map<String, dynamic> model;

  const _KnethDropdown(this.model, {super.key});

  @override
  State<_KnethDropdown> createState() => _KnethDropdownState();
}

class _KnethDropdownState extends State<_KnethDropdown> {
  late final StacFormValues _values;
  late final StacFieldRegistration _registration;
  late final List<FieldOption> _staticOptions;
  DynamicOptionsController? _dynamic;
  void Function()? _removeStatusListener;
  Map<String, DynamicFieldOptionsStatus> _statuses = const {};
  bool _listening = false;
  bool _isRequired = false;

  /// The status suffix currently shown after the label (' (select a
  /// dependency first)' etc.), set by build. The required-error uses the
  /// label *as displayed*, suffix included, so it tells the agent why the
  /// field is empty — the wording the previous renderer already produced, because
  /// it validates with the overlaid label (STAC_MIGRATION_SCOPING.md 12.6,
  /// decided 2026-09-24).
  String _suffix = '';

  String get _id => widget.model['id'] as String;
  String get _label => widget.model['label'] as String? ?? _id;
  bool get _isDynamic => widget.model['dynamicConfig'] != null;

  @override
  void initState() {
    super.initState();
    final scope = KnethStacScope.of(context);
    _values = scope.values;
    _registration = StacFieldRegistration(
      id: _id,
      validate: () =>
          validateRequiredValue(label: '$_label$_suffix', value: _values[_id], required: _isRequired, trim: true),
    );
    _values.register(_registration);

    _staticOptions = ((widget.model['options'] as List?) ?? const [])
        .map((o) => FieldOption.fromJson((o as Map).cast<String, dynamic>()))
        .toList();

    if (_isDynamic) {
      final config = (widget.model['dynamicConfig'] as Map).cast<String, dynamic>();
      final field = FieldConfig(
        key: _id,
        label: _label,
        type: FieldType.select,
        inputMode: FieldInputMode.dynamic_,
        property: FieldProperty(
          order: 0,
          isRequired: false,
          isHidden: false,
          dependsOn: ((widget.model['dependsOn'] as List?) ?? const []).cast<String>(),
          dynamicConfig: DynamicConfig.fromJson(config),
        ),
      );
      _dynamic = DynamicOptionsController(
        apiClient: scope.apiClient,
        stage: StageConfig(stageId: 'stac:$_id', title: _label, screenType: ScreenType.genericForm, fields: [field]),
        clientId: scope.clientId,
        workflowId: scope.workflowId,
        onOptionsResolved: scope.onOptionsResolved,
      );
      _values.addListener(_onValuesChanged);
      // `state` is protected outside a StateNotifier subclass, so statuses
      // are cached from its listener. The listener fires once immediately
      // (empty), then on every status change; setState is only allowed
      // once initState has finished.
      _removeStatusListener = _dynamic!.addListener((statuses) {
        _statuses = statuses;
        if (_listening && mounted) setState(() {});
      });
      // First sync establishes the initial status (ready / not ready) and
      // returns nothing to clear.
      _dynamic!.sync(_values.snapshot);
      _listening = true;
    }
  }

  void _onValuesChanged() {
    final cleared = _dynamic!.sync(_values.snapshot);
    if (cleared.contains(_id)) _values.update(_id, null);
  }

  @override
  void dispose() {
    _values.unregister(_registration);
    if (_isDynamic) {
      _values.removeListener(_onValuesChanged);
      _removeStatusListener?.call();
      // Deliberately not `_dynamic.dispose()`: a StateNotifier throws if
      // its state is set after dispose, and a fetch can still be in
      // flight when the agent leaves the stage. It holds no timers or
      // streams, so dropping the reference is enough.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _isRequired = KnethEffectiveField.resolveRequired(context, widget.model);

    var options = _staticOptions;
    var suffix = '';
    AppException? failure;
    if (_isDynamic) {
      switch (_statuses[_id]) {
        case null || DynamicFieldOptionsNotReady():
          options = const [];
          suffix = ' (select a dependency first)';
        case DynamicFieldOptionsLoading():
          options = const [];
          suffix = ' (loading...)';
        case DynamicFieldOptionsReady(:final fieldOptions):
          options = fieldOptions;
        case DynamicFieldOptionsFailed(:final error):
          options = const [];
          suffix = ' (failed to load)';
          failure = error;
      }
    }

    _suffix = suffix;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failure != null) AppErrorView(error: failure, onRetry: () => _dynamic!.retry(_id)),
          ListenableBuilder(
            listenable: Listenable.merge([_values, _values.errors]),
            builder: (context, _) {
              final current = _values[_id] as String?;
              final selectable = options.any((o) => o.value == current) ? current : null;
              return DropdownButtonFormField<String>(
                // Re-created when the options or the selection change so the
                // form field's own internal value can't go stale.
                key: ValueKey('kneth_dropdown_field:$_id:${options.map((o) => o.value).join(',')}:$selectable'),
                initialValue: selectable,
                isExpanded: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: '$_label$suffix',
                  errorText: _values.errors.value[_id],
                ),
                items: [for (final o in options) DropdownMenuItem(value: o.value, child: Text(o.label))],
                onChanged: (value) {
                  if (value != null) _values.update(_id, value);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
