import 'package:flutter/material.dart';

/// Draws a signature's pen strokes on a white background. Shared by the
/// dedicated `SignatureCaptureScreen` and the Stac `kneth_signature_capture`
/// widget (`features/stac_rendering/`) so the two can't drift apart.
class SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter oldDelegate) => true;
}
