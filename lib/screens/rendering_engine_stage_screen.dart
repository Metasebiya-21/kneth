import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kifiya_rendering_engine/kifiya_rendering_engine.dart' as engine;

import '../controllers/flow_controller.dart';
import '../models/stage_config.dart';
import '../services/rendering_engine_adapter.dart';
import '../theme/app_colors.dart';
import '../widgets/digital_id_card_preview.dart';
import '../widgets/stripe_identity_stepper.dart';

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

  bool _isFaydaStage(engine.FormSchema schema) {
    return schema.fields.any(
      (f) =>
          f.id.toLowerCase().contains('fayda') ||
          f.label.toLowerCase().contains('fayda') ||
          f.id.toLowerCase().contains('nationalid') ||
          f.label.toLowerCase().contains('national id'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: StripeIdentityStepper(
        currentStep: widget.controller.stepNumber,
        totalSteps: widget.controller.totalSteps > 0 ? widget.controller.totalSteps : 4,
        stageTitle: widget.stage.title,
        flowTitle: widget.controller.manifest.title,
        onBack: () {
          widget.controller.back();
          if (Navigator.of(context).canPop() && widget.controller.progressLabel == 'Step 01') {
            Navigator.of(context).pop();
          }
        },
      ),
      body: FutureBuilder<engine.FormSchema>(
        future: _schemaFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.error.withAlpha(40)),
                      ),
                      child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 36),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Could not load stage schema:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => setState(_loadSchema),
                      child: const Text('Retry Stage'),
                    ),
                  ],
                ),
              ),
            );
          }

          final schema = snapshot.data!;
          final initialValues = widget.controller.valuesForStage(widget.stage.stageId);
          final hasFaydaField = _isFaydaStage(schema);

          return ProviderScope(
            key: ValueKey(widget.stage.stageId),
            overrides: [
              engine.formControllerProvider.overrideWith(
                (ref) => engine.FormController()..seed(initialValues),
              ),
              engine.formErrorsProvider.overrideWith((ref) => <String, String>{}),
            ],
            child: Consumer(
              builder: (context, ref, child) {
                final formCtrl = ref.watch(engine.formControllerProvider);

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Fayda Card
                      if (hasFaydaField) ...[
                        ListenableBuilder(
                          listenable: formCtrl,
                          builder: (context, _) {
                            final faydaVal = formCtrl.getValue('faydaNumber') ??
                                formCtrl.getValue('fayda_id') ??
                                formCtrl.getValue('national_id') ??
                                '';
                            final nameVal = formCtrl.getValue('fullName') ??
                                formCtrl.getValue('full_name') ??
                                formCtrl.getValue('name') ??
                                '';
                            final dobVal = formCtrl.getValue('dob') ?? formCtrl.getValue('dateOfBirth');
                            final genderVal = formCtrl.getValue('gender');

                            return DigitalIdCardPreview(
                              faydaNumber: faydaVal.toString(),
                              fullName: nameVal.toString(),
                              dateOfBirth: dobVal?.toString(),
                              gender: genderVal?.toString(),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Security Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary.withAlpha(30)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 18),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Encrypted Field Collection',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.textPrimary),
                                  ),
                                  Text(
                                    'Inputs verified against Ethiopian banking & NID specs.',
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Form Container
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: AppColors.cardDecorationElevated,
                        child: engine.DynamicForm(
                          schema: schema,
                          controller: _formController,
                          showSubmitButton: false,
                          onSubmit: widget.controller.submitStage,
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
            boxShadow: [
              BoxShadow(color: AppColors.shadowLight, blurRadius: 16, offset: Offset(0, -4)),
            ],
          ),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: const Text(
              'Continue to Next Stage',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: 0.2),
            ),
            onPressed: _onContinue,
          ),
        ),
      ),
    );
  }
}
