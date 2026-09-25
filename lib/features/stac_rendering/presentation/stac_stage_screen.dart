import 'package:flutter/material.dart';
import 'package:stac/stac.dart';

import '../../../services/api_client.dart';
import '../../native_capture/data/media_storage_repository_impl.dart';
import '../../native_capture/domain/media_storage_repository.dart';
import '../../flow/domain/field_config.dart';
import '../../flow/domain/hidden_field_values.dart';
import '../../liveness/presentation/liveness_launcher.dart';
import 'knet_stac_scope.dart';
import 'stac_bootstrap.dart';
import 'stac_form_values.dart';
import 'stac_visibility.dart';

/// Renders one stage from its Stac `widget` JSON — the Stac-path
/// replacement for the previous form screen (GENERIC_FORM) *and* for the
/// two native-capture screens, since on the Stac route a NATIVE_CAPTURE
/// stage is just a single `kneth_photo_capture` / `kneth_signature_capture`
/// widget (section 11.3).
///
/// Same external contract as the old screens: shows the stage title and
/// progress label, and on Continue hands the collected values to
/// [onSubmit] — which the flow wires to `FlowNotifier.submitStage`, so the
/// flat `stageId.fieldKey` payload `ApiClientImpl.submitCase` sends is built
/// by the same code as before. The difference is only who produced the
/// values: [StacFormValues], whose semantics deliberately mirror the old
/// the previous renderer's form-state notifier (see its doc comment).
///
/// Continue runs every mounted field's async `prepare` (the signature
/// export), then validation; if anything fails the errors are shown on the
/// fields and nothing is submitted.
class StacStageScreen extends StatefulWidget {
  final String title;
  final String progressLabel;
  final Map<String, dynamic> widgetJson;
  final Map<String, dynamic> initialValues;
  /// [values] is what is sent; [remembered] is what currently-hidden fields held
  /// (not sent, kept so the answer can reappear if the field is re-revealed).
  final void Function(Map<String, dynamic> values, {Map<String, dynamic> remembered}) onSubmit;
  final ApiClient apiClient;
  final String clientId;
  final String caseId;
  final String workflowId;

  /// Normally left null (production gets the real
  /// [MediaStorageRepositoryImpl]); tests pass a fake, the same seam
  /// `PhotoCaptureScreen`/`SignatureCaptureScreen` use.
  final MediaStorageRepository? mediaRepository;

  /// Normally left null (the real camera). See [PickPhoto].
  final PickPhoto? pickPhoto;

  /// Normally left null (the real selfie check). See [CaptureLiveness].
  final CaptureLiveness? captureLiveness;

  /// Told about live options each dropdown fetches (see
  /// `resolvedOptionsProvider`); null when nobody needs them.
  final void Function(String fieldKey, List<FieldOption> options)? onOptionsResolved;

  const StacStageScreen({
    super.key,
    required this.title,
    required this.progressLabel,
    required this.widgetJson,
    required this.initialValues,
    required this.onSubmit,
    required this.apiClient,
    required this.clientId,
    required this.caseId,
    required this.workflowId,
    this.mediaRepository,
    this.pickPhoto,
    this.captureLiveness,
    this.onOptionsResolved,
  });

  @override
  State<StacStageScreen> createState() => _StacStageScreenState();
}

class _StacStageScreenState extends State<StacStageScreen> {
  late final StacFormValues _values = StacFormValues(widget.initialValues);
  Widget? _tree;
  bool _submitting = false;
  late final List<FieldConfig> _visibilityFields;

  @override
  void initState() {
    super.initState();
    _visibilityFields = visibilityFieldsIn(widget.widgetJson);
    ensureKnethStacInitialized();
  }

  @override
  void dispose() {
    _values.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final errors = await _values.validateAll();
      if (!mounted || errors.isNotEmpty) return;
      // Hidden-right-now fields' values are not sent, but are remembered.
      final parts = partitionHiddenFieldValues(_visibilityFields, _values.snapshot);
      widget.onSubmit(parts.kept, remembered: parts.dropped);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Center(child: Text(widget.progressLabel)),
          const SizedBox(width: 16),
        ],
      ),
      body: KnethStacScope(
        values: _values,
        apiClient: widget.apiClient,
        clientId: widget.clientId,
        caseId: widget.caseId,
        workflowId: widget.workflowId,
        mediaRepository: widget.mediaRepository ?? const MediaStorageRepositoryImpl(),
        pickPhoto: widget.pickPhoto ?? pickPhotoWithCamera,
        captureLiveness: widget.captureLiveness ?? launchLivenessCapture,
        onOptionsResolved: widget.onOptionsResolved,
        child: Builder(
          builder: (context) {
            // Parsed once: rebuilding this screen must not re-parse the tree
            // (Stac re-runs JSON -> widget every time it's asked).
            _tree ??= Stac.fromJson(widget.widgetJson, context) ?? const SizedBox.shrink();
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_tree!]),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _submitting ? null : _onContinue,
            child: const Text('Continue'),
          ),
        ),
      ),
    );
  }
}
