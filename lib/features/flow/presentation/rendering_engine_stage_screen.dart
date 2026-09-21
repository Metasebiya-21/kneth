import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kifiya_rendering_engine/kifiya_rendering_engine.dart' as engine;

import '../../../widgets/app_error_view.dart';
import '../data/rendering_engine_adapter.dart';
import '../domain/field_config.dart';
import '../domain/stage_config.dart';
import 'dynamic_options_controller.dart';
import 'flow_notifier.dart';

/// Renders one GENERIC_FORM stage through the kifiya_rendering_engine
/// plugin's [engine.DynamicForm]. Unlike native_capture/sync's screens,
/// this one is flow's *own* presentation code, so it reads
/// [flowNotifierProvider] directly via its own `ref` rather than going
/// through the [FlowSession] facade — that facade exists specifically for
/// other features to depend on, not for flow to depend on itself.
///
/// The plugin's form state lives in a global Riverpod provider
/// (`formControllerProvider`), not one scoped per form instance, so each
/// stage gets its own [ProviderScope] (keyed by stageId so Flutter actually
/// tears down and rebuilds it on stage change) with that provider
/// overridden to a fresh, pre-seeded [engine.FormController] — otherwise
/// values from a previous stage would leak into the next one.
/// [DynamicOptionsController] gets the same per-stage treatment, for the
/// same reason.
///
/// Field visibility/required-ness is recomputed on kneth's side on every
/// value change (see [visibleFieldSchemasFor]) rather than left to the
/// plugin to interpret — the [_StageFormView] below rebuilds the schema
/// handed to [engine.DynamicForm] each time the form's values change, and
/// [DynamicOptionsController.sync] hooks into that exact same rebuild to
/// keep DYNAMIC fields' options in step too, rather than a second,
/// parallel change-detection path.
class RenderingEngineStageScreen extends ConsumerStatefulWidget {
  final StageConfig stage;

  const RenderingEngineStageScreen({super.key, required this.stage});

  @override
  ConsumerState<RenderingEngineStageScreen> createState() => _RenderingEngineStageScreenState();
}

class _RenderingEngineStageScreenState extends ConsumerState<RenderingEngineStageScreen> {
  final engine.DynamicFormController _formController = engine.DynamicFormController();
  late final List<engine.FieldSchema> _allFieldSchemas;

  @override
  void initState() {
    super.initState();
    // No network call left in here (see rendering_engine_adapter.dart) —
    // ENUM options are static and DYNAMIC options are resolved reactively
    // by DynamicOptionsController — so this is synchronous now.
    _allFieldSchemas = buildStageFieldSchemas(stage: widget.stage);
  }

  void _onContinue() {
    _formController.submit(ref.read(flowNotifierProvider.notifier).submitStage);
  }

  @override
  Widget build(BuildContext context) {
    final viewState = ref.watch(flowNotifierProvider);
    final progressLabel = viewState is FlowViewReady ? viewState.caseState.progressLabel : '';
    final initialValues = viewState is FlowViewReady
        ? viewState.caseState.valuesForStage(widget.stage.stageId)
        : <String, dynamic>{};
    final apiClient = ref.read(apiClientProvider);
    // The already-resolved manifest's own workflowId/clientId — not the
    // original FlowManifest input — since that's the resume-accurate
    // source of truth (see DynamicOptionsController's own doc comment).
    // This screen is only ever reached once viewState is FlowViewReady
    // (see FlowScreen._buildStage), so the fallback below is defensive,
    // not an expected path.
    final workflowId = viewState is FlowViewReady ? viewState.caseState.manifest.workflowId : '';
    final clientId = viewState is FlowViewReady ? viewState.caseState.manifest.clientId : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stage.title),
        actions: [
          Center(child: Text(progressLabel)),
          const SizedBox(width: 16),
        ],
      ),
      body: ProviderScope(
        key: ValueKey(widget.stage.stageId),
        overrides: [
          engine.formControllerProvider.overrideWith(
            (ref) => engine.FormController()..seed(initialValues),
          ),
          engine.formErrorsProvider.overrideWith((ref) => <String, String>{}),
          dynamicOptionsControllerProvider.overrideWith(
            (ref) => DynamicOptionsController(
              apiClient: apiClient,
              stage: widget.stage,
              clientId: clientId,
              workflowId: workflowId,
            ),
          ),
        ],
        child: _StageFormView(
          stage: widget.stage,
          allFieldSchemas: _allFieldSchemas,
          initialValues: initialValues,
          formController: _formController,
          onSubmit: ref.read(flowNotifierProvider.notifier).submitStage,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _onContinue,
            child: const Text('Continue'),
          ),
        ),
      ),
    );
  }
}

class _StageFormView extends ConsumerStatefulWidget {
  final StageConfig stage;
  final List<engine.FieldSchema> allFieldSchemas;
  final Map<String, dynamic> initialValues;
  final engine.DynamicFormController formController;
  final void Function(Map<String, dynamic>) onSubmit;

  const _StageFormView({
    required this.stage,
    required this.allFieldSchemas,
    required this.initialValues,
    required this.formController,
    required this.onSubmit,
  });

  @override
  ConsumerState<_StageFormView> createState() => _StageFormViewState();
}

class _StageFormViewState extends ConsumerState<_StageFormView> {
  @override
  void initState() {
    super.initState();
    // Deferred a frame for the same reason every other provider-mutating
    // side effect in this app is (see NOTES.md's initState gotcha):
    // sync() writes to dynamicOptionsControllerProvider's state, and
    // ref.listen below only fires on *changes*, not on registration, so
    // fields already pre-filled (e.g. from a resumed case) need this one
    // explicit initial call.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dynamicOptionsControllerProvider.notifier).sync(widget.initialValues);
    });
  }

  @override
  Widget build(BuildContext context) {
    final values = ref.watch(engine.formControllerProvider);
    final dynamicStatuses = ref.watch(dynamicOptionsControllerProvider);

    // The same rebuild that recomputes visibility (visibleFieldSchemasFor,
    // below) is what drives DYNAMIC re-fetching — one reactive point, not
    // two. sync() itself only does real work when something's actually
    // changed (see DynamicOptionsController), so this is a cheap no-op on
    // most rebuilds.
    ref.listen(engine.formControllerProvider, (previous, next) {
      final cleared = ref.read(dynamicOptionsControllerProvider.notifier).sync(next);
      if (cleared.isEmpty) return;
      final formNotifier = ref.read(engine.formControllerProvider.notifier);
      for (final key in cleared) {
        formNotifier.updateField(key, null, ref);
      }
    });

    final fieldsByKey = {for (final field in widget.stage.fields) field.key: field};
    final visible = visibleFieldSchemasFor(
      stage: widget.stage,
      allFieldSchemas: widget.allFieldSchemas,
      values: values,
    );
    final overlaid = visible
        .map((schema) => _overlayDynamicStatus(schema, fieldsByKey[schema.id], dynamicStatuses[schema.id]))
        .toList();

    final failedFields = widget.stage.fields.where(
      (field) =>
          field.inputMode == FieldInputMode.dynamic_ && dynamicStatuses[field.key] is DynamicFieldOptionsFailed,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final field in failedFields)
            AppErrorView(
              error: (dynamicStatuses[field.key] as DynamicFieldOptionsFailed).error,
              onRetry: () => ref.read(dynamicOptionsControllerProvider.notifier).retry(field.key),
            ),
          engine.DynamicForm(
            schema: engine.FormSchema(
              title: widget.stage.title,
              fields: overlaid,
              submitApiUrl: '',
              nextFormApiUrl: '',
            ),
            controller: widget.formController,
            showSubmitButton: false,
            onSubmit: widget.onSubmit,
          ),
        ],
      ),
    );
  }

  /// DYNAMIC fields' options/label aren't known at schema-build time (see
  /// rendering_engine_adapter.dart) — this fills them in from
  /// [DynamicOptionsController]'s live status every rebuild. The plugin's
  /// dropdown has no built-in "disabled"/"loading" concept (it always
  /// renders an enabled `DropdownButtonFormField`, see
  /// kifiya_rendering_engine's DropdownFieldWidget), so an empty options
  /// list plus a label suffix is the closest approximation of
  /// disabled/not-yet-available achievable without modifying that plugin.
  engine.FieldSchema _overlayDynamicStatus(
    engine.FieldSchema schema,
    FieldConfig? field,
    DynamicFieldOptionsStatus? status,
  ) {
    if (field == null || field.inputMode != FieldInputMode.dynamic_) return schema;

    return switch (status) {
      null || DynamicFieldOptionsNotReady() => schema.copyWith(
          label: '${field.label} (select a dependency first)',
          options: const [],
        ),
      DynamicFieldOptionsLoading() => schema.copyWith(
          label: '${field.label} (loading...)',
          options: const [],
        ),
      DynamicFieldOptionsReady(:final options) => schema.copyWith(
          label: field.label,
          options: options,
        ),
      DynamicFieldOptionsFailed() => schema.copyWith(
          label: '${field.label} (failed to load)',
          options: const [],
        ),
    };
  }

}
