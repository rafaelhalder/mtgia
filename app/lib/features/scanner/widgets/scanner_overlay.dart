import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Overlay visual para guiar posicionamento da carta
class ScannerOverlay extends StatelessWidget {
  final bool isProcessing;
  final String? detectedName;

  const ScannerOverlay({
    super.key,
    this.isProcessing = false,
    this.detectedName,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScannerOverlayPainter(
        isProcessing: isProcessing,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final bool isProcessing;

  _ScannerOverlayPainter({
    this.isProcessing = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Área da carta (proporção 63:88 - padrão MTG)
    // Tamanho moderado — ~65% da largura, centralizado levemente acima
    final cardWidth = size.width * 0.65;
    final cardHeight = cardWidth * (88 / 63);
    final left = (size.width - cardWidth) / 2;
    final top = (size.height - cardHeight) / 2 - 30;

    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, cardWidth, cardHeight),
      const Radius.circular(12),
    );

    // Escurecimento sutil fora da área do cartão
    final dimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    final dimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(cardRect);
    dimPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, dimPaint);

    // Borda do guia — loomCyan (mythicGold se processando)
    final borderColor = isProcessing ? AppTheme.mythicGold : AppTheme.loomCyan.withValues(alpha: 0.8);
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(cardRect, borderPaint);

    // Corners decorativos
    _drawCorners(canvas, left, top, cardWidth, cardHeight, borderColor);
  }

  void _drawCorners(
    Canvas canvas,
    double left,
    double top,
    double width,
    double height,
    Color color,
  ) {
    final cornerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const cs = 22.0;

    // Top-left
    canvas.drawLine(Offset(left - 1, top + cs), Offset(left - 1, top - 1), cornerPaint);
    canvas.drawLine(Offset(left - 1, top - 1), Offset(left + cs, top - 1), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(left + width - cs, top - 1), Offset(left + width + 1, top - 1), cornerPaint);
    canvas.drawLine(Offset(left + width + 1, top - 1), Offset(left + width + 1, top + cs), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(left - 1, top + height - cs), Offset(left - 1, top + height + 1), cornerPaint);
    canvas.drawLine(Offset(left - 1, top + height + 1), Offset(left + cs, top + height + 1), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(left + width - cs, top + height + 1), Offset(left + width + 1, top + height + 1), cornerPaint);
    canvas.drawLine(Offset(left + width + 1, top + height - cs), Offset(left + width + 1, top + height + 1), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.isProcessing != isProcessing;
  }
}
