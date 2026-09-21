enum FieldType { text, select, unknown }

enum FieldInputMode { free, enumMode, dynamic_, date, unknown }

class FieldOption {
  final String label;
  final String value;

  FieldOption({required this.label, required this.value});

  factory FieldOption.fromJson(Map<String, dynamic> json) {
    return FieldOption(
      label: json['label'] as String,
      value: json['value'] as String,
    );
  }
}

class DynamicConfig {
  final String endpoint;
  final String method;

  DynamicConfig({required this.endpoint, required this.method});

  factory DynamicConfig.fromJson(Map<String, dynamic> json) {
    return DynamicConfig(
      endpoint: json['endpoint'] as String? ?? '',
      method: json['method'] as String? ?? 'GET',
    );
  }
}

/// Comparison used by a [FieldCondition]. Only [eq] is implemented today;
/// new operators can be added here without changing the JSON shape or
/// breaking existing conditions, which fall back to [unknown] (never
/// matches) if the string isn't recognized yet.
enum ConditionOp { eq, unknown }

class FieldCondition {
  final String field;
  final ConditionOp op;
  final dynamic value;

  FieldCondition({required this.field, required this.op, required this.value});

  factory FieldCondition.fromJson(Map<String, dynamic> json) {
    return FieldCondition(
      field: json['field'] as String,
      op: _parseOp(json['op'] as String?),
      value: json['value'],
    );
  }

  static ConditionOp _parseOp(String? raw) {
    switch (raw) {
      case 'eq':
        return ConditionOp.eq;
      default:
        return ConditionOp.unknown;
    }
  }

  bool evaluate(Map<String, dynamic> values) {
    switch (op) {
      case ConditionOp.eq:
        return values[field] == value;
      case ConditionOp.unknown:
        return false;
    }
  }
}

/// The isRequired/isHidden overrides applied when a [ConditionalDependency]
/// resolves to "then" or "else". Either may be left unset, meaning "don't
/// override the field's base property".
class ConditionalOutcome {
  final bool? isRequired;
  final bool? isHidden;

  const ConditionalOutcome({this.isRequired, this.isHidden});

  factory ConditionalOutcome.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ConditionalOutcome();
    return ConditionalOutcome(
      isRequired: json['isRequired'] as bool?,
      isHidden: json['isHidden'] as bool?,
    );
  }
}

class ConditionalDependency {
  final List<FieldCondition> ifConditions;
  final ConditionalOutcome then;
  final ConditionalOutcome orElse;

  ConditionalDependency({
    required this.ifConditions,
    required this.then,
    this.orElse = const ConditionalOutcome(),
  });

  factory ConditionalDependency.fromJson(Map<String, dynamic> json) {
    return ConditionalDependency(
      ifConditions: (json['if'] as List<dynamic>? ?? [])
          .map((c) => FieldCondition.fromJson(c as Map<String, dynamic>))
          .toList(),
      then: ConditionalOutcome.fromJson(json['then'] as Map<String, dynamic>?),
      orElse: ConditionalOutcome.fromJson(json['else'] as Map<String, dynamic>?),
    );
  }

  /// Returns the outcome for the given in-progress form [values]: "then"
  /// if every condition matches, "else" otherwise.
  ConditionalOutcome resolve(Map<String, dynamic> values) {
    final matches = ifConditions.every((condition) => condition.evaluate(values));
    return matches ? then : orElse;
  }
}

class FieldProperty {
  final int order;
  final bool isRequired;
  final bool isHidden;
  final int? minLen;
  final int? maxLen;
  final String? regex;
  final List<FieldOption>? options;
  final DynamicConfig? dynamicConfig;
  final List<String> dependsOn;
  final ConditionalDependency? conditionalDependency;

  FieldProperty({
    required this.order,
    required this.isRequired,
    required this.isHidden,
    this.minLen,
    this.maxLen,
    this.regex,
    this.options,
    this.dynamicConfig,
    this.dependsOn = const [],
    this.conditionalDependency,
  });

  factory FieldProperty.fromJson(Map<String, dynamic> json) {
    return FieldProperty(
      order: json['order'] as int? ?? 0,
      isRequired: json['isRequired'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      minLen: json['minLen'] as int?,
      maxLen: json['maxLen'] as int?,
      regex: json['regex'] as String?,
      options: (json['options'] as List<dynamic>?)
          ?.map((option) => FieldOption.fromJson(option as Map<String, dynamic>))
          .toList(),
      dynamicConfig: json['dynamicConfig'] != null
          ? DynamicConfig.fromJson(json['dynamicConfig'] as Map<String, dynamic>)
          : null,
      dependsOn: (json['dependsOn'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      conditionalDependency: json['conditionalDependency'] != null
          ? ConditionalDependency.fromJson(
              json['conditionalDependency'] as Map<String, dynamic>)
          : null,
    );
  }

}

/// A field's resolved isRequired/isHidden for a given set of in-progress
/// form values — see [FieldConfig.effectiveState]. This is always computed
/// on kneth's side; it is never handed to kifiya_rendering_engine as a
/// condition for the plugin to interpret itself, only as the final
/// show/hide + required booleans to render.
class EffectiveFieldState {
  final bool isRequired;
  final bool isHidden;

  const EffectiveFieldState({required this.isRequired, required this.isHidden});
}

class FieldConfig {
  final String key;
  final String label;
  final FieldType type;
  final FieldInputMode inputMode;
  final FieldProperty property;

  /// The value the backend wants pre-populated when this field is first
  /// shown (e.g. carried over from a prior case, or a client-level
  /// default). Field-level, not stage-level, and a plain string — matching
  /// the confirmed backend contract's `ManifestFieldResponse.prefill`
  /// (`str | None`) exactly; this used to live on [StageConfig] as a
  /// `Map<String, dynamic>?`, a shape that was never checked against a
  /// live contract until NOTES.md's Phase 1b investigation found the
  /// mismatch. Genuinely unpopulated by the real backend today (its own
  /// doc comment says so), so still not consumed by anything beyond
  /// [FlowCaseState.valuesForStage]'s fallback.
  final String? prefill;

  /// Whether this field requires an explicit consent capture before the
  /// case can proceed. Field-level for the same reason as [prefill] — see
  /// NOTES.md. Not consumed by any screen yet; carried through only so the
  /// shape matches what the confirmed contract actually sends.
  final bool? consentRequired;

  FieldConfig({
    required this.key,
    required this.label,
    required this.type,
    required this.inputMode,
    required this.property,
    this.prefill,
    this.consentRequired,
  });

  /// The single source of truth for whether this field is currently
  /// required/hidden, given the stage's in-progress [values]. Supports any
  /// [ConditionalDependency] shape, including a multi-clause "if" array —
  /// unlike kifiya_rendering_engine's own dependsOn/visibleWhenEquals,
  /// which only understands a single equality check. Pure computation over
  /// this field's own config and the values passed in — no I/O, which is
  /// exactly why it belongs in domain/ rather than the data/ adapter that
  /// used to house the (broken, single-condition-only) version of this
  /// logic.
  EffectiveFieldState effectiveState(Map<String, dynamic> values) {
    final dependency = property.conditionalDependency;
    if (dependency == null) {
      return EffectiveFieldState(isRequired: property.isRequired, isHidden: property.isHidden);
    }
    final outcome = dependency.resolve(values);
    return EffectiveFieldState(
      isRequired: outcome.isRequired ?? property.isRequired,
      isHidden: outcome.isHidden ?? property.isHidden,
    );
  }

  factory FieldConfig.fromJson(Map<String, dynamic> json) {
    return FieldConfig(
      key: json['key'] as String,
      label: json['label'] as String,
      type: _parseType(json['type'] as String?),
      inputMode: _parseInputMode(json['inputMode'] as String?),
      property: FieldProperty.fromJson(
        json['property'] as Map<String, dynamic>? ?? {},
      ),
      prefill: json['prefill'] as String?,
      consentRequired: json['consentRequired'] as bool?,
    );
  }

  static FieldType _parseType(String? raw) {
    switch (raw) {
      case 'TEXT':
        return FieldType.text;
      case 'SELECT':
        return FieldType.select;
      default:
        return FieldType.unknown;
    }
  }

  static FieldInputMode _parseInputMode(String? raw) {
    switch (raw) {
      case 'FREE':
        return FieldInputMode.free;
      case 'ENUM':
        return FieldInputMode.enumMode;
      case 'DYNAMIC':
        return FieldInputMode.dynamic_;
      case 'DATE':
        return FieldInputMode.date;
      default:
        return FieldInputMode.unknown;
    }
  }
}
