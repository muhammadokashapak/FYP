import 'package:flutter/material.dart';

import '../services/inference_service.dart';

/// Widget that draws bounding boxes and labels over the camera preview.
/// Uses CustomPaint with a DetectionPainter to render detection results
/// with color coding based on confidence levels.
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.detections,
  });

  final List<DetectionResult> detections;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DetectionPainter(detections),
      size: Size.infinite,
    );
  }
}

/// CustomPainter that draws bounding boxes and confidence labels.
/// Box colors vary by confidence:
///   - High confidence (>75%): green
///   - Medium confidence (50-75%): amber
class DetectionPainter extends CustomPainter {
  DetectionPainter(this.detections);

  final List<DetectionResult> detections;

  // Paint styles
  static const double _boxStrokeWidth = 2.0;
  static const double _labelPillHeight = 18.0;
  static const double _labelPillRadius = 4.0;
  static const double _labelTextSize = 12.0;
  static const double _labelPadding = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      _drawDetection(canvas, size, detection);
    }
  }

  void _drawDetection(Canvas canvas, Size size, DetectionResult detection) {
    // Convert normalized Rect to canvas coordinates
    final canvasRect = Rect.fromLTWH(
      detection.boundingBox.left * size.width,
      detection.boundingBox.top * size.height,
      detection.boundingBox.width * size.width,
      detection.boundingBox.height * size.height,
    );

    // Determine box color based on confidence
    final boxColor = detection.confidence >= 0.75
        ? const Color(0xFF4CAF50) // Green for high confidence
        : const Color(0xFFFFA726); // Amber for medium confidence

    // Draw bounding box
    final boxPaint = Paint()
      ..color = boxColor
      ..strokeWidth = _boxStrokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(canvasRect, const Radius.circular(4));
    canvas.drawRRect(rrect, boxPaint);

    // Prepare label text
    final confidence = (detection.confidence * 100).round();
    final labelText = '${detection.label} $confidence%';

    // Draw label pill (background)
    final textPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: _labelTextSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Pill dimensions (slightly wider than text)
    final pillWidth = textPainter.width + (_labelPadding * 2);
    final pillHeight = _labelPillHeight;

    // Determine pill position: above box if possible, else below
    Rect pillRect;
    if (canvasRect.top > pillHeight + 4) {
      // Draw above box
      pillRect = Rect.fromLTWH(
        canvasRect.left,
        canvasRect.top - pillHeight - 2,
        pillWidth,
        pillHeight,
      );
    } else {
      // Draw below box
      pillRect = Rect.fromLTWH(
        canvasRect.left,
        canvasRect.bottom + 2,
        pillWidth,
        pillHeight,
      );
    }

    // Draw pill background
    final pillPaint = Paint()
      ..color = boxColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final pillRRect =
        RRect.fromRectAndRadius(pillRect, const Radius.circular(_labelPillRadius));
    canvas.drawRRect(pillRRect, pillPaint);

    // Draw label text inside pill
    textPainter.paint(
      canvas,
      Offset(
        pillRect.left + _labelPadding,
        pillRect.top + (pillHeight - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    // Repaint if detection list changes
    return oldDelegate.detections != detections;
  }

  @override
  bool shouldRebuildSemantics(DetectionPainter oldDelegate) => false;
}
