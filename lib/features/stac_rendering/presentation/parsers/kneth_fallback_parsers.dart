import 'package:flutter/widgets.dart';
import 'package:stac/stac.dart';

import '../../../../services/app_exception.dart';
import '../../../../widgets/app_error_view.dart';

/// `kneth_unsupported_field` — the backend's marker for a field/input-mode
/// combination it can't map to a widget (section 11.3). The previous renderer
/// *threw* `UnsupportedError` for the equivalent and took the whole stage
/// screen down; this renders a plain-language notice in the field's place
/// through the shared [AppErrorView] and lets the rest of the form work.
/// Non-blocking: the marker carries no `required` information.
class KnethUnsupportedFieldParser extends StacParser<Map<String, dynamic>> {
  const KnethUnsupportedFieldParser();

  @override
  String get type => 'kneth_unsupported_field';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) {
    final id = model['id'] as String? ?? 'this field';
    final kind = '${model['fieldType'] ?? '?'}/${model['inputMode'] ?? '?'}';
    // ClientException: the closest existing category ("the request/content
    // can't be processed, retrying won't help"); its message is shown as-is.
    return AppErrorView(
      error: ClientException(422, "'$id' can't be shown in this version of the app (unsupported field type $kind)."),
    );
  }
}

/// `kneth_native_capture` — a NATIVE_CAPTURE stage whose handler isn't
/// photo/signature (section 11.3, keeps the handler name). Mirrors the old
/// `_buildNativeCapturePlaceholder`: say so, don't crash, and let the agent
/// continue (nothing is registered, so Continue submits no values — the old
/// placeholder submitted `{}` too).
class KnethNativeCaptureParser extends StacParser<Map<String, dynamic>> {
  const KnethNativeCaptureParser();

  @override
  String get type => 'kneth_native_capture';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) {
    final label = model['label'] as String? ?? model['id'] as String? ?? 'This step';
    final handler = model['handler'] as String?;
    return AppErrorView(
      error: ClientException(
        422,
        "'$label' needs a capture type${handler == null ? '' : " ('$handler')"} that this version of the app doesn't support.",
      ),
    );
  }
}
