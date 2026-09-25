import 'dart:collection';

import 'package:flutter/foundation.dart';

/// One registered field's submit-time hooks. [prepare] runs before any
/// validation (the signature widget exports its canvas there); [validate]
/// returns an error message or null.
class StacFieldRegistration {
  final String id;
  final String? Function() validate;
  final Future<void> Function()? prepare;

  const StacFieldRegistration({required this.id, required this.validate, this.prepare});
}

/// The host-owned form-values notifier the custom Stac parsers read and
/// write (STAC_MIGRATION_SCOPING.md section 4's Option A': Stac itself has
/// no reactivity, so the host owns the state and each parser listens).
///
/// Semantics deliberately mirror the previous renderer's form-state notifier
/// so the submitted payload is identical:
/// - the map is replaced, never mutated in place (`{...state, id: value}`),
///   so a snapshot handed to `DynamicOptionsController` can be diffed
///   against a later one;
/// - clearing a value stores an explicit `null` (the key stays), exactly as
///   the previous notifier's `updateField(id, null)` did — it is not removed;
/// - untouched fields are simply absent.
class StacFormValues extends ChangeNotifier {
  Map<String, dynamic> _values;
  final ValueNotifier<Map<String, String>> errors = ValueNotifier(const {});
  final Map<String, StacFieldRegistration> _registrations = {};

  StacFormValues([Map<String, dynamic>? initial]) : _values = {...?initial};

  dynamic operator [](String id) => _values[id];

  /// The current values. Never mutated after being handed out (see class doc).
  Map<String, dynamic> get snapshot => UnmodifiableMapView(_values);

  void update(String id, dynamic value) {
    if (_values.containsKey(id) && _values[id] == value) return;
    _values = {..._values, id: value};
    if (errors.value.containsKey(id)) {
      errors.value = {...errors.value}..remove(id);
    }
    notifyListeners();
  }

  void register(StacFieldRegistration registration) => _registrations[registration.id] = registration;

  void unregister(StacFieldRegistration registration) {
    if (identical(_registrations[registration.id], registration)) {
      _registrations.remove(registration.id);
    }
  }

  /// Runs every mounted field's [StacFieldRegistration.prepare], then its
  /// validation, publishes the messages to [errors] and returns them. A
  /// field that is hidden is not mounted, so it is neither prepared nor
  /// validated — the same "hidden fields are never validated" behavior the
  /// the previous renderer got by never handing them to the engine.
  Future<Map<String, String>> validateAll() async {
    final registrations = _registrations.values.toList();
    for (final registration in registrations) {
      await registration.prepare?.call();
    }
    final found = <String, String>{};
    for (final registration in registrations) {
      final message = registration.validate();
      if (message != null) found[registration.id] = message;
    }
    errors.value = found;
    return found;
  }

  @override
  void dispose() {
    errors.dispose();
    super.dispose();
  }
}
