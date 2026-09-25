import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/api_client.dart';
import '../../flow/domain/field_config.dart';
import '../../liveness/presentation/liveness_launcher.dart';
import '../../native_capture/domain/media_storage_repository.dart';
import 'stac_form_values.dart';

/// Opens the camera and returns the captured file's path, or null if the
/// agent backed out. The default is the real `image_picker` camera call; a
/// test passes its own (including one that throws the `PlatformException`s
/// image_picker raises for a denied permission).
typedef PickPhoto = Future<String?> Function();

Future<String?> pickPhotoWithCamera() async {
  final photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
  return photo?.path;
}

/// What every custom Stac parser needs from the host. An InheritedWidget
/// rather than a Riverpod read because parsers only receive a `BuildContext`
/// from Stac, and the values notifier is a `ChangeNotifier` each parser
/// listens to directly — the scope itself never changes, hence
/// [updateShouldNotify] false.
class KnethStacScope extends InheritedWidget {
  final StacFormValues values;
  final ApiClient apiClient;
  final String clientId;

  /// The case this stage belongs to: keys the backend's liveness attempt count.
  final String caseId;
  final String workflowId;
  final MediaStorageRepository mediaRepository;
  final PickPhoto pickPhoto;

  /// Opens the selfie check. See [CaptureLiveness].
  final CaptureLiveness captureLiveness;

  /// Forwarded to each live dropdown's `DynamicOptionsController`.
  final void Function(String fieldKey, List<FieldOption> options)? onOptionsResolved;

  const KnethStacScope({
    super.key,
    required this.values,
    required this.apiClient,
    required this.clientId,
    required this.caseId,
    required this.workflowId,
    required this.mediaRepository,
    this.pickPhoto = pickPhotoWithCamera,
    this.captureLiveness = launchLivenessCapture,
    this.onOptionsResolved,
    required super.child,
  });

  static KnethStacScope of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<KnethStacScope>();
    assert(scope != null, 'A kneth_* Stac widget was built outside a KnethStacScope.');
    return scope!;
  }

  @override
  bool updateShouldNotify(KnethStacScope oldWidget) => false;
}

/// The resolved required-ness a `kneth_conditional` wrapper hands to the
/// field it wraps (from the real `FieldConfig.effectiveState`), so the field
/// doesn't need its JSON re-parsed each time a condition flips. A field with
/// no wrapper falls back to its own `required` value.
class KnethEffectiveField extends InheritedWidget {
  final bool isRequired;

  const KnethEffectiveField({super.key, required this.isRequired, required super.child});

  static bool resolveRequired(BuildContext context, Map<String, dynamic> model) {
    final inherited = context.dependOnInheritedWidgetOfExactType<KnethEffectiveField>();
    return inherited?.isRequired ?? (model['required'] as bool? ?? false);
  }

  @override
  bool updateShouldNotify(KnethEffectiveField oldWidget) => isRequired != oldWidget.isRequired;
}
