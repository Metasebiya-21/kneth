import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stac/stac.dart';

import '../../../../services/app_exception.dart';
import '../../../../widgets/app_error_view.dart';
import '../../../native_capture/domain/captured_media.dart';
import '../../../native_capture/domain/retake_photo_use_case.dart';
import '../knet_stac_scope.dart';
import '../stac_form_values.dart';

/// The key every native-capture stage stores its file under. Not the
/// widget's `id` (that is the *stage* id): `SyncScreen` finds captured files
/// by the `stageId.filePath` suffix and `SyncRepositoryImpl` maps the stage
/// to a document kind, so the Stac path has to write the same key or upload
/// silently finds nothing.
const String kCapturedFilePathKey = 'filePath';

/// `kneth_photo_capture` — `{type, id, label}` where `id` is the stage id
/// (section 11.3). Real implementation, not the spike's mechanism-only one:
/// persistence goes through `MediaStorageRepository` (copy out of the
/// OS-clearable cache into app storage, exactly as `PhotoCaptureScreen`
/// does), retake goes through the existing, tested [RetakePhotoUseCase]
/// (delete the discarded file), and the camera permission outcomes
/// image_picker reports are handled.
///
/// Permission handling, read from image_picker's platform source (Android:
/// `ImagePickerDelegate` raises `camera_access_denied`; iOS:
/// `FLTImagePickerPlugin` raises `camera_access_denied` and
/// `camera_access_restricted`), and the app manifests already declare
/// `CAMERA` / `NSCameraUsageDescription`. Those become a plain-language
/// [ForbiddenException] through the shared [AppErrorView]. That the real
/// OS dialogs behave this way on a device is not verified here.
class KnethPhotoCaptureParser extends StacParser<Map<String, dynamic>> {
  const KnethPhotoCaptureParser();

  @override
  String get type => 'kneth_photo_capture';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) =>
      _KnethPhotoCapture(model, key: ValueKey('kneth_photo_capture:${model['id']}'));
}

class _KnethPhotoCapture extends StatefulWidget {
  final Map<String, dynamic> model;

  const _KnethPhotoCapture(this.model, {super.key});

  @override
  State<_KnethPhotoCapture> createState() => _KnethPhotoCaptureState();
}

class _KnethPhotoCaptureState extends State<_KnethPhotoCapture> {
  late final KnethStacScope _scope;
  late final StacFieldRegistration _registration;
  String? _path;
  bool _capturing = false;
  AppException? _error;

  StacFormValues get _values => _scope.values;
  String get _stageId => widget.model['id'] as String;

  @override
  void initState() {
    super.initState();
    _scope = KnethStacScope.of(context);
    _path = _values[kCapturedFilePathKey] as String?;
    // A photo is mandatory on a capture stage — the old screen only offered
    // Confirm once one existed.
    _registration = StacFieldRegistration(
      id: _stageId,
      validate: () => _values[kCapturedFilePathKey] == null ? 'Take a photo to continue' : null,
    );
    _values.register(_registration);
  }

  @override
  void dispose() {
    _values.unregister(_registration);
    super.dispose();
  }

  Future<void> _capture() async {
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final picked = await _scope.pickPhoto();
      if (picked == null) return;
      final media = await _scope.mediaRepository.persistCopy(
        sourcePath: picked,
        prefix: _stageId,
        type: CaptureType.photo,
      );
      if (!mounted) return;
      setState(() => _path = media.filePath);
      _values.update(kCapturedFilePathKey, media.filePath);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = _permissionAwareError(e));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } catch (e) {
      if (mounted) setState(() => _error = const UnknownException());
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  AppException _permissionAwareError(PlatformException e) {
    switch (e.code) {
      case 'camera_access_denied':
        return const ForbiddenException(
          'Camera access is turned off for this app. Turn it on in Settings, then try again.',
        );
      case 'camera_access_restricted':
        return const ForbiddenException('Camera access is restricted on this device.');
      default:
        return const UnknownException();
    }
  }

  Future<void> _retake() async {
    final previous = _path;
    setState(() => _path = null);
    _values.update(kCapturedFilePathKey, null);
    await RetakePhotoUseCase(_scope.mediaRepository).execute(previous);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 260, child: Center(child: _buildPreview())),
          if (_error != null) AppErrorView(error: _error!),
          const SizedBox(height: 8),
          _path == null
              ? ElevatedButton.icon(
                  onPressed: _capturing ? null : _capture,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_capturing ? 'Opening camera...' : 'Take photo'),
                )
              : OutlinedButton(onPressed: _retake, child: const Text('Retake')),
          ValueListenableBuilder<Map<String, String>>(
            valueListenable: _values.errors,
            builder: (context, errors, _) {
              final message = errors[_stageId];
              if (message == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_path == null) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.document_scanner_outlined, size: 64),
          SizedBox(height: 16),
          Text('No photo captured yet'),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(_path!),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_outlined, size: 64),
      ),
    );
  }
}
