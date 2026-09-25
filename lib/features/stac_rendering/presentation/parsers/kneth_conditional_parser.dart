import 'package:flutter/widgets.dart';
import 'package:stac/stac.dart';

import '../../../flow/domain/field_config.dart';
import '../knet_stac_scope.dart';
import '../stac_visibility.dart';

/// `kneth_conditional` — the envelope the backend wraps around any field
/// that has a `conditionalDependency` (STAC_MIGRATION_SCOPING.md 11.2/11.3):
///
/// ```json
/// {"type": "kneth_conditional",
///  "property": {"isRequired", "isHidden", "dependsOn", "conditionalDependency"},
///  "child": {<one field widget>}}
/// ```
///
/// Visibility and required-ness are NOT re-implemented here. The envelope's
/// `property` is parsed by the existing [FieldProperty.fromJson] and asked
/// via the existing [FieldConfig.effectiveState] — the same
/// `ConditionalDependency.resolve` (AND of clauses) the previous renderer's screen used, and
/// the same unit tests cover. The spike's 12-line copy of that logic is
/// deliberately not used. Stac's built-in `conditional` widget and its
/// expression evaluator are not used either (section 2.4/11.2).
class KnethConditionalParser extends StacParser<Map<String, dynamic>> {
  const KnethConditionalParser();

  @override
  String get type => 'kneth_conditional';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) => _KnethConditional(model);
}

class _KnethConditional extends StatefulWidget {
  final Map<String, dynamic> model;

  const _KnethConditional(this.model);

  @override
  State<_KnethConditional> createState() => _KnethConditionalState();
}

class _KnethConditionalState extends State<_KnethConditional> {
  late final FieldConfig _field;
  Widget? _child;

  @override
  void initState() {
    super.initState();
    // Shared with the submit path, so what is hidden on screen and what is
    // dropped at submit come from the same FieldConfig (see stac_visibility.dart).
    _field = fieldConfigForConditional(widget.model);
  }

  @override
  Widget build(BuildContext context) {
    final values = KnethStacScope.of(context).values;
    return ListenableBuilder(
      listenable: values,
      builder: (context, _) {
        final state = _field.effectiveState(values.snapshot);
        // A hidden field is unmounted, so it isn't validated (and its
        // TextEditingController etc. are disposed); its value stays in the
        // form values, exactly as the previous renderer did.
        if (state.isHidden) return const SizedBox.shrink();
        // Parsed once and cached: the child instance stays identical across
        // rebuilds, and only its required-ness (below) changes.
        _child ??= Stac.fromJson((widget.model['child'] as Map).cast<String, dynamic>(), context) ??
            const SizedBox.shrink();
        return KnethEffectiveField(isRequired: state.isRequired, child: _child!);
      },
    );
  }
}
