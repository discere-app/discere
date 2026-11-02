import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Draws [qrCode] as black modules, filling the space it is given. The
/// background and quiet zone are the caller's: this paints only the code.
class QrCodeView extends StatelessWidget {
  final QrCode qrCode;

  const QrCodeView({required this.qrCode, super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(painter: _QrModulePainter(QrImage(qrCode))),
    );
  }
}

class _QrModulePainter extends CustomPainter {
  final QrImage image;

  _QrModulePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final moduleSize = size.shortestSide / count;
    // Each row's dark modules are merged into runs and painted without
    // anti-aliasing — adjacent anti-aliased squares at fractional offsets
    // leave faint seams between them, which can trip up a scanner.
    final path = Path();
    for (var row = 0; row < count; row++) {
      var col = 0;
      while (col < count) {
        if (!image.isDark(row, col)) {
          col++;
          continue;
        }
        final start = col;
        while (col < count && image.isDark(row, col)) {
          col++;
        }
        path.addRect(
          Rect.fromLTRB(
            start * moduleSize,
            row * moduleSize,
            col * moduleSize,
            (row + 1) * moduleSize,
          ),
        );
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_QrModulePainter oldDelegate) =>
      oldDelegate.image != image;
}
