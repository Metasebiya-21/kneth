import 'package:flutter/material.dart';
import 'package:stac/stac.dart';

import '../../domain/field_validation.dart';
import '../knet_stac_scope.dart';
import '../stac_form_values.dart';

/// `kneth_date` — Stac has no date-picker widget at all (2.3), so this is
/// the whole implementation. Carries over the previous renderer's date
/// field: tap opens `showDatePicker` (1900-2100, initial date =
/// the current value or today), the stored value is `toIso8601String()`, the
/// display is the ISO date part, or "Select Date" when empty. The adapter
/// never passes min/max dates or a format, so neither is honored here.
class KnethDateParser extends StacParser<Map<String, dynamic>> {
  const KnethDateParser();

  @override
  String get type => 'kneth_date';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) =>
      _KnethDate(model, key: ValueKey('kneth_date:${model['id']}'));
}

class _KnethDate extends StatefulWidget {
  final Map<String, dynamic> model;

  const _KnethDate(this.model, {super.key});

  @override
  State<_KnethDate> createState() => _KnethDateState();
}

class _KnethDateState extends State<_KnethDate> {
  late final StacFormValues _values;
  late final StacFieldRegistration _registration;
  bool _isRequired = false;

  String get _id => widget.model['id'] as String;
  String get _label => widget.model['label'] as String? ?? _id;

  @override
  void initState() {
    super.initState();
    _values = KnethStacScope.of(context).values;
    _registration = StacFieldRegistration(
      id: _id,
      validate: () => validateRequiredValue(label: _label, value: _values[_id], required: _isRequired, trim: false),
    );
    _values.register(_registration);
  }

  @override
  void dispose() {
    _values.unregister(_registration);
    super.dispose();
  }

  Future<void> _pick(String? current) async {
    final firstDate = DateTime(1900);
    final lastDate = DateTime(2100);
    final now = DateTime.now();
    final initialDate = current != null
        ? DateTime.parse(current)
        : now.isAfter(lastDate)
            ? lastDate
            : now.isBefore(firstDate)
                ? firstDate
                : now;
    final picked = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: initialDate,
    );
    if (picked != null) _values.update(_id, picked.toIso8601String());
  }

  @override
  Widget build(BuildContext context) {
    _isRequired = KnethEffectiveField.resolveRequired(context, widget.model);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ListenableBuilder(
        listenable: Listenable.merge([_values, _values.errors]),
        builder: (context, _) {
          final value = _values[_id] as String?;
          return InkWell(
            onTap: () => _pick(value),
            child: InputDecorator(
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _label,
                errorText: _values.errors.value[_id],
              ),
              child: Text(
                value != null ? value.split('T').first : 'Select Date',
                style: TextStyle(color: value != null ? Colors.black87 : Colors.black54),
              ),
            ),
          );
        },
      ),
    );
  }
}
