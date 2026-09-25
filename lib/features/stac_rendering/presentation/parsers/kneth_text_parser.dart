import 'package:flutter/material.dart';
import 'package:stac/stac.dart';

import '../../domain/field_validation.dart';
import '../knet_stac_scope.dart';
import '../stac_form_values.dart';

/// `kneth_text` — replaces the built-in `textFormField`, which cannot report
/// changes to the host (STAC_MIGRATION_SCOPING.md 2.5).
///
/// Carries over the previous renderer's text field (read from its
/// source): outline-bordered field, label and hint both the label, the
/// error shown as `errorText`, every keystroke written to the form values.
/// No required marker is drawn, because the old widget draws none. Submit
/// validation is [validateTextField] (required, regex, and minLen/maxLen).
class KnethTextParser extends StacParser<Map<String, dynamic>> {
  const KnethTextParser();

  @override
  String get type => 'kneth_text';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) =>
      _KnethText(model, key: ValueKey('kneth_text:${model['id']}'));
}

class _KnethText extends StatefulWidget {
  final Map<String, dynamic> model;

  const _KnethText(this.model, {super.key});

  @override
  State<_KnethText> createState() => _KnethTextState();
}

class _KnethTextState extends State<_KnethText> {
  late final TextEditingController _controller;
  late final StacFormValues _values;
  late final StacFieldRegistration _registration;
  bool _isRequired = false;

  String get _id => widget.model['id'] as String;
  String get _label => widget.model['label'] as String? ?? _id;

  @override
  void initState() {
    super.initState();
    _values = KnethStacScope.of(context).values;
    _reportUncompilableRegex();
    // Restores whatever's in the form values — seeded from a resumed case,
    // or left over from before this field was hidden and shown again.
    _controller = TextEditingController(text: _values[_id]?.toString() ?? '');
    _registration = StacFieldRegistration(
      id: _id,
      validate: () => validateTextField(
        label: _label,
        value: _values[_id],
        required: _isRequired,
        regex: widget.model['regex'] as String?,
        minLen: widget.model['minLen'] as int?,
        maxLen: widget.model['maxLen'] as int?,
      ),
    );
    _values.register(_registration);
  }

  /// A regex that compiles in neither mode silently disables this field's
  /// format check (see [validateTextField]) — the field still accepts input,
  /// so this reports through [FlutterError.reportError] (loud console banner
  /// in debug, `FlutterError.onError` — crash reporting — in release) instead
  /// of throwing, and does not put anything in front of the end user, who
  /// can't fix a config. Once per mount, naming the field and the pattern.
  void _reportUncompilableRegex() {
    final regex = widget.model['regex'] as String?;
    if (regex == null || isCompilableRegex(regex)) return;
    FlutterError.reportError(FlutterErrorDetails(
      exception: FormatException(
        'Field "$_id" has a regex that does not compile in Dart; its format check is disabled',
        regex,
      ),
      library: 'kneth_text',
      context: ErrorDescription('while validating text field "$_id" with pattern "$regex"'),
    ));
  }

  @override
  void dispose() {
    _values.unregister(_registration);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _isRequired = KnethEffectiveField.resolveRequired(context, widget.model);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ValueListenableBuilder<Map<String, String>>(
        valueListenable: _values.errors,
        builder: (context, errors, _) => TextFormField(
          controller: _controller,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: _label,
            hintText: _label,
            errorText: errors[_id],
          ),
          onChanged: (value) => _values.update(_id, value),
        ),
      ),
    );
  }
}
