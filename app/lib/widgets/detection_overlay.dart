import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../services/inference_service.dart';

/// Draws premium detection boxes with corner brackets over camera / image previews.
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.detections,
  });

  final List<DetectionResult> detections;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DetectionPainter(detections: detections),
      size: Size.infinite,
    );
  }
}

class DetectionPainter extends CustomPainter {
  DetectionPainter({required this.detections});

  final List<DetectionResult> detections;

  static const double _cornerRatio = 0.18;
  static const double _strokeWidth = 3.0;
  static const double _labelTextSize = 13.0;
  static const double _labelPadding = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    for (final detection in detections) {
      if (detection.boundingBox.width < 0.02 ||
          detection.boundingBox.height < 0.02) {
        continue;
      }
      _drawPremiumBoundingBox(canvas, size, detection);
    }
  }

  void _drawPremiumBoundingBox(
    Canvas canvas,
    Size size,
    DetectionResult detection,
  ) {
    final box = detection.boundingBox;
    final rect = Rect.fromLTWH(
      box.left * size.width,
      box.top * size.height,
      box.width * size.width,
      box.height * size.height,
    );

    if (rect.width <= 0 || rect.height <= 0) return;

    final color = AppColors.detectionBoxColor(detection.confidence);
    final cornerLen = math.min(rect.width, rect.height) * _cornerRatio;

    // Soft inner glow fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withValues(alpha: 0.14),
          color.withValues(alpha: 0.04),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      fillPaint,
    );

    // Outer subtle border
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      borderPaint,
    );

    // Corner brackets
    final bracketPaint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawCornerBrackets(canvas, rect, cornerLen, bracketPaint);

    // Label pill
    final confidence = (detection.confidence * 100).round();
    final labelText = '${detection.label}  $confidence%';

    final textPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: _labelTextSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width - 8);

    final pillWidth = textPainter.width + (_labelPadding * 2);
    final pillHeight = 28.0;
    final pillLeft =
        rect.left.clamp(0.0, size.width - pillWidth).toDouble();
    final pillTop = (rect.top > pillHeight + 8
            ? rect.top - pillHeight - 6
            : rect.top + 6)
        .toDouble();

    final pillRect = Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        pillRect.shift(const Offset(0, 2)),
        const Radius.circular(8),
      ),
      shadowPaint,
    );

    final pillPaint = Paint()
      ..shader = LinearGradient(
        colors: [color, color.withValues(alpha: 0.75)],
      ).createShader(pillRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(8)),
      pillPaint,
    );

    textPainter.paint(
      canvas,
      Offset(
        pillRect.left + _labelPadding,
        pillRect.top + (pillHeight - textPainter.height) / 2,
      ),
    );
  }

  void _drawCornerBrackets(
    Canvas canvas,
    Rect rect,
    double len,
    Paint paint,
  ) {
    final tl = rect.topLeft;
    final tr = rect.topRight;
    final bl = rect.bottomLeft;
    final br = rect.bottomRight;

    // Top-left
    canvas.drawLine(tl, tl + Offset(len, 0), paint);
    canvas.drawLine(tl, tl + Offset(0, len), paint);
    // Top-right
    canvas.drawLine(tr, tr + Offset(-len, 0), paint);
    canvas.drawLine(tr, tr + Offset(0, len), paint);
    // Bottom-left
    canvas.drawLine(bl, bl + Offset(len, 0), paint);
    canvas.drawLine(bl, bl + Offset(0, -len), paint);
    // Bottom-right
    canvas.drawLine(br, br + Offset(-len, 0), paint);
    canvas.drawLine(br, br + Offset(0, -len), paint);
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
