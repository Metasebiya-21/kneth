import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kifiya_rendering_engine/kifiya_rendering_engine.dart' as engine;

import '../controllers/flow_controller.dart';
import '../models/stage_config.dart';
import '../services/rendering_engine_adapter.dart';

/// Renders one GENERIC_FORM stage through the kifiya_rendering_engine
/// plugin's [engine.DynamicForm], while kneth's own [FlowController] keeps
/// owning stage progression, persistence, and sync.
///
/// The plugin's form state lives in a global Riverpod provider
/// (`formControllerProvider`), not one scoped per form instance, so each
/// stage gets its own [ProviderScope] (keyed by stageId so Flutter actually
/// tears down and rebuilds it on stage change) with that provider
/// overridden to a fresh, pre-seeded [engine.FormController] — otherwise
/// values from a previous stage would leak into the next one.
class RenderingEngineStageScreen extends StatefulWidget {
  final FlowController controller;
  final StageConfig stage;

  const RenderingEngineStageScreen({
    super.key,
    required this.controller,
    required this.stage,
  });

  @override
  State<RenderingEngineStageScreen> createState() => _RenderingEngineStageScreenState();
}

class _RenderingEngineStageScreenState extends State<RenderingEngineStageScreen> {
  final engine.DynamicFormController _formController = engine.DynamicFormController();
  late Future<engine.FormSchema> _schemaFuture;

  @override
  void initState() {
    super.initState();
    _loadSchema();
  }

  void _loadSchema() {
    _schemaFuture = buildFormSchema(
      stage: widget.stage,
      apiClient: widget.controller.apiClient,
    );
  }

  void _onContinue() {
    _formController.submit(widget.controller.submitStage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stage.title),
        actions: [
          Center(child: Text(widget.controller.progressLabel)),
          const SizedBox(width: 16),
        ],
      ),
      body: FutureBuilder<engine.FormSchema>(
        future: _schemaFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not load this stage: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(_loadSchema),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final initialValues = widget.controller.valuesForStage(widget.stage.stageId);
          return ProviderScope(
            key: ValueKey(widget.stage.stageId),
            overrides: [
              engine.formControllerProvider.overrideWith(
                (ref) => engine.FormController()..seed(initialValues),
              ),
              engine.formErrorsProvider.overrideWith((ref) => <String, String>{}),
            ],
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: engine.DynamicForm(
                schema: snapshot.data!,
                controller: _formController,
                showSubmitButton: false,
                onSubmit: widget.controller.submitStage,
              ),
            ),
          );
        },
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
