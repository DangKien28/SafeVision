import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:safe_vision_app/features/detection/domain/entities/bounding_box_entity.dart';

class BoundingBoxPainter extends CustomPainter {
  final List<BoundingBoxEntity> boxes;
  final Size imageSize;

  BoundingBoxPainter({required this.boxes, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.red;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // =========================
    // FIX SCALE CHUẨN CAMERA
    // =========================
    final scale = math.max(
      size.width / imageSize.width,
      size.height / imageSize.height,
    );

    final dx = (size.width - imageSize.width * scale) / 2;
    final dy = (size.height - imageSize.height * scale) / 2;

    // DEBUG
    debugPrint(
      'Canvas=${size.width}x${size.height} '
      'Image=${imageSize.width}x${imageSize.height} '
      'scale=$scale dx=$dx dy=$dy',
    );

    for (final box in boxes) {
      final rect = Rect.fromLTRB(
        box.x1 * scale + dx,
        box.y1 * scale + dy,
        box.x2 * scale + dx,
        box.y2 * scale + dy,
      );

      canvas.drawRect(rect, paint);

      // Label
      textPainter.text = TextSpan(
        text: box.label,
        style: const TextStyle(
          color: Colors.red,
          fontSize: 14,
          backgroundColor: Colors.black54,
        ),
      );

      textPainter.layout();
      textPainter.paint(canvas, Offset(rect.left, rect.top - 18));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.boxes != boxes || oldDelegate.imageSize != imageSize;
  }
}
