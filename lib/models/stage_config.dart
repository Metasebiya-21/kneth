import 'field_config.dart';

enum ScreenType { genericForm, nativeCapture, unknown }

/// Which native screen a NATIVE_CAPTURE stage renders. Unrecognized/null
/// values fall back to a generic placeholder in flow_screen.dart rather
/// than crashing.
enum NativeHandler { photoCapture, signatureCapture, unknown }

NativeHandler parseNativeHandler(String? raw) {
  switch (raw) {
    case 'photo_capture':
      return NativeHandler.photoCapture;
    case 'signature_capture':
      return NativeHandler.signatureCapture;
    default:
      return NativeHandler.unknown;
  }
}

ScreenType _parseScreenType(String? raw) {
  switch (raw) {
    case 'GENERIC_FORM':
      return ScreenType.genericForm;
    case 'NATIVE_CAPTURE':
      return ScreenType.nativeCapture;
    default:
      return ScreenType.unknown;
  }
}

class StageConfig {
  final String stageId;
  final String title;
  final ScreenType screenType;
  final List<FieldConfig> fields;
  final NativeHandler nativeHandler;

  StageConfig({
    required this.stageId,
    required this.title,
    required this.screenType,
    required this.fields,
    this.nativeHandler = NativeHandler.unknown,
  });

  /// Parses a stage descriptor as returned by [ApiClient.fetchNextStage] —
  /// the server-driven shape of one flow step.
  factory StageConfig.fromJson(Map<String, dynamic> json) {
    return StageConfig(
      stageId: json['stageId'] as String,
      title: json['title'] as String,
      screenType: _parseScreenType(json['screenType'] as String?),
      fields: (json['fields'] as List<dynamic>? ?? [])
          .map((field) => FieldConfig.fromJson(field as Map<String, dynamic>))
          .toList(),
      nativeHandler: parseNativeHandler(json['nativeHandler'] as String?),
    );
  }
}