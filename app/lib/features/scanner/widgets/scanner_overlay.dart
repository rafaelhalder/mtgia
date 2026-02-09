import 'package:flutter/material.dart';

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
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    // Área da carta (proporção 63:88 - padrão MTG)
    final cardWidth = size.width * 0.85;
    final cardHeight = cardWidth * (88 / 63);
    final left = (size.width - cardWidth) / 2;
    final top = (size.height - cardHeight) / 2;

    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, cardWidth, cardHeight),
      const Radius.circular(16),
    );

    // Desenha área escura fora do card
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(cardRect);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);

    // Borda do guia
    final borderPaint = Paint()
      ..color = isProcessing ? Colors.amber : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(cardRect, borderPaint);

    // Área do nome (topo da carta) - highlight verde
    final namePaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    
    final nameRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(left, top, cardWidth, cardHeight * 0.12),
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
    );
    canvas.drawRRect(nameRect, namePaint);

    // Borda da área do nome
    final nameBorderPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(nameRect, nameBorderPaint);

    // Corners decorativos
    _drawCorners(canvas, left, top, cardWidth, cardHeight);
  }

  void _drawCorners(
    Canvas canvas,
    double left,
    double top,
    double width,
    double height,
  ) {
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const cornerSize = 30.0;

    // Top-left
    canvas.drawLine(
      Offset(left, top + cornerSize),
      Offset(left, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left + cornerSize, top),
      cornerPaint,
    );

    // Top-right
    canvas.drawLine(
      Offset(left + width - cornerSize, top),
      Offset(left + width, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + width, top),
      Offset(left + width, top + cornerSize),
      cornerPaint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(left, top + height - cornerSize),
      Offset(left, top + height),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top + height),
      Offset(left + cornerSize, top + height),
      cornerPaint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(left + width - cornerSize, top + height),
      Offset(left + width, top + height),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + width, top + height - cornerSize),
      Offset(left + width, top + height),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.isProcessing != isProcessing;
  }
}

/// Widget para mostrar dicas de uso
class ScannerTips extends StatelessWidget {
  const ScannerTips({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                'Dicas',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTip('Alinhe o NOME na área verde'),
          _buildTip('Boa iluminação melhora a leitura'),
          _buildTip('Evite reflexos em cartas foil'),
          _buildTip('Mantenha a carta reta'),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
