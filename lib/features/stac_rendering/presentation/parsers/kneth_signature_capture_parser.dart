import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:stac/stac.dart';

import '../../../native_capture/domain/captured_media.dart';
import '../../../native_capture/presentation/signature_painter.dart';
import '../knet_stac_scope.dart';
import '../stac_form_values.dart';
import 'kneth_photo_capture_parser.dart' show kCapturedFilePathKey;

/// `kneth_signature_capture` — `{type, id, label}` (section 11.3). The
/// scoping doc explicitly did not prototype this, so it is not assumed to be
/// photo capture's twin. Two things are genuinely different:
///
/// 1. **The export can't happen on tap.** The old screen exports the canvas
///    (`RenderRepaintBoundary.toImage` then `toByteData`, both async and
///    the second off the frame scheduler) on its own Confirm button. Here
///    the stage screen's Continue submits, so the export runs as this
///    field's [StacFieldRegistration.prepare], awaited by `validateAll()`
///    before any value is read.
/// 2. **A pan recognizer inside a scroll view loses to the scroll.** The
///    form stage is scrollable; a vertical stroke on a plain
///    `GestureDetector(onPan…)` is claimed by the scroll view's drag first.
///    The canvas therefore uses an [EagerGestureRecognizer] (claims the
///    pointer immediately) plus raw pointer events for the positions.
///
/// Same painter as the old screen ([SignaturePainter]); same 3.0 pixel
/// ratio; same `persistBytes` call. The file is stored under
/// [kCapturedFilePathKey].
class KnethSignatureCaptureParser extends StacParser<Map<String, dynamic>> {
  const KnethSignatureCaptureParser();

  @override
  String get type => 'kneth_signature_capture';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) =>
      _KnethSignatureCapture(model, key: ValueKey('kneth_signature_capture:${model['id']}'));
}

class _KnethSignatureCapture extends StatefulWidget {
  final Map<String, dynamic> model;

  const _KnethSignatureCapture(this.model, {super.key});

  @override
  State<_KnethSignatureCapture> createState() => _KnethSignatureCaptureState();
}

class _KnethSignatureCaptureState extends State<_KnethSignatureCapture> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  late final KnethStacScope _scope;
  late final StacFieldRegistration _registration;
  String? _savedPath;
  bool _dirty = false;

  StacFormValues get _values => _scope.values;
  String get _stageId => widget.model['id'] as String;

  @override
  void initState() {
    super.initState();
    _scope = KnethStacScope.of(context);
    _registration = StacFieldRegistration(
      id: _stageId,
      prepare: _exportIfNeeded,
      validate: () => _strokes.isEmpty ? 'Sign in the box to continue' : null,
    );
    _values.register(_registration);
  }

  @override
  void dispose() {
    _values.unregister(_registration);
    super.dispose();
  }

  Future<void> _exportIfNeeded() async {
    if (_strokes.isEmpty || !_dirty || !mounted) return;
    final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final media = await _scope.mediaRepository.persistBytes(
      bytes: byteData!.buffer.asUint8List(),
      prefix: _stageId,
      type: CaptureType.signature,
    );
    final previous = _savedPath;
    if (previous != null) await _scope.mediaRepository.deleteFile(previous);
    _savedPath = media.filePath;
    _dirty = false;
    _values.update(kCapturedFilePathKey, media.filePath);
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _dirty = false;
    });
    _values.update(kCapturedFilePathKey, null);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Sign inside the box below', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: RepaintBoundary(
                key: _boundaryKey,
                child: RawGestureDetector(
                  gestures: {
                    EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                      EagerGestureRecognizer.new,
                      (_) {},
                    ),
                  },
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) => setState(() {
                      _strokes.add([event.localPosition]);
                      _dirty = true;
                    }),
                    onPointerMove: (event) => setState(() {
                      if (_strokes.isNotEmpty) _strokes.last.add(event.localPosition);
                    }),
                    child: CustomPaint(painter: SignaturePainter(_strokes), size: Size.infinite),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _strokes.isEmpty ? null : _clear, child: const Text('Clear')),
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
}
