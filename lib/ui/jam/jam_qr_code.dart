import 'package:flutter/material.dart';
import 'package:zxing2/qrcode.dart';

class JamQrCode extends StatelessWidget {
  const JamQrCode({super.key, required this.data, this.size = 240});
  final String data;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Código QR de acceso temporal a esta Jam',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _JamQrPainter(data)),
    ),
  );
}

class _JamQrPainter extends CustomPainter {
  _JamQrPainter(String data)
    : qr = Encoder.encode(data, ErrorCorrectionLevel.m);
  final QRCode qr;
  @override
  void paint(Canvas canvas, Size size) {
    final matrix = qr.matrix!;
    final cells = matrix.width + 8;
    final scale = (size.shortestSide / cells).floorToDouble().clamp(1.0, 100.0);
    final left = (size.width - scale * cells) / 2;
    final top = (size.height - scale * cells) / 2;
    // Fijos en cualquier tema: un QR solo se escanea en negro sobre blanco.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xffffffff),
    );
    final ink = Paint()
      ..color = const Color(0xff000000)
      ..isAntiAlias = false;
    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        if (matrix.get(x, y) == 1) {
          canvas.drawRect(
            Rect.fromLTWH(
              left + (x + 4) * scale,
              top + (y + 4) * scale,
              scale,
              scale,
            ),
            ink,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_JamQrPainter oldDelegate) =>
      qr.matrix != oldDelegate.qr.matrix;
}
