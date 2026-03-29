import 'package:flutter/material.dart';
import '../../domain/entities/detection_object.dart';

/// CustomPainter vẽ bounding box + label cho tất cả vật thể phát hiện được
class BoundingBoxPainter extends CustomPainter {
  final List<DetectionObject> detections;
  final bool mirrorHorizontal;

  const BoundingBoxPainter({
    required this.detections,
    this.mirrorHorizontal = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      _drawDetection(canvas, size, detection);
    }
  }

  void _drawDetection(Canvas canvas, Size size, DetectionObject detection) {
    final box = detection.boundingBox;

    // Scale từ normalized [0,1] sang pixel
    double left = box.left * size.width;
    double top = box.top * size.height;
    double right = box.right * size.width;
    double bottom = box.bottom * size.height;

    // Mirror nếu camera trước
    if (mirrorHorizontal) {
      final tmp = left;
      left = size.width - right;
      right = size.width - tmp;
    }

    final rect = Rect.fromLTRB(left, top, right, bottom);
    final color =
        detection.isDangerous ? Colors.red : _colorForLabel(detection.label);

    // ── Vẽ viền bounding box ──────────────────────────────
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // ── Vẽ góc bracket (corner markers) ──────────────────
    _drawCornerBrackets(canvas, rect, color);

    // ── Vẽ nhãn + confidence ─────────────────────────────
    final labelText =
        '${detection.label}  ${(detection.confidence * 100).toStringAsFixed(0)}%';

    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);

    final lw = tp.width + 12;
    final lh = tp.height + 6;
    final lt = (top - lh - 2).clamp(0.0, size.height - lh);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, lt, lw, lh),
        const Radius.circular(4),
      ),
      Paint()..color = color.withOpacity(0.9),
    );
    tp.paint(canvas, Offset(left + 6, lt + 3));

    // ── Vẽ chấm tâm ───────────────────────────────────────
    canvas.drawCircle(
      Offset((left + right) / 2, (top + bottom) / 2),
      4,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Color color) {
    const len = 16.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void drawBracket(List<Offset> pts) {
      final path = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy);
      canvas.drawPath(path, paint);
    }

    // Top-left
    drawBracket([
      Offset(rect.left, rect.top + len),
      Offset(rect.left, rect.top),
      Offset(rect.left + len, rect.top),
    ]);
    // Top-right
    drawBracket([
      Offset(rect.right - len, rect.top),
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.top + len),
    ]);
    // Bottom-left
    drawBracket([
      Offset(rect.left, rect.bottom - len),
      Offset(rect.left, rect.bottom),
      Offset(rect.left + len, rect.bottom),
    ]);
    // Bottom-right
    drawBracket([
      Offset(rect.right - len, rect.bottom),
      Offset(rect.right, rect.bottom),
      Offset(rect.right, rect.bottom - len),
    ]);
  }

  Color _colorForLabel(String label) {
    const palette = [
      Colors.greenAccent,
      Colors.cyanAccent,
      Colors.orangeAccent,
      Colors.purpleAccent,
      Colors.tealAccent,
      Colors.pinkAccent,
      Colors.amberAccent,
      Colors.lightBlueAccent,
    ];
    return palette[label.hashCode.abs() % palette.length];
  }

  @override
  bool shouldRepaint(BoundingBoxPainter old) {
    if (old.detections.length != detections.length) return true;
    if (old.mirrorHorizontal != mirrorHorizontal) return false;
    // So sánh nhanh bằng reference — Equatable đã override ==
    for (int i = 0; i < detections.length; i++) {
      if (old.detections[i] != detections[i]) return true;
    }
    return false;
  }
}

/// Widget bọc painter, dùng với Stack lên CameraPreview
class BoundingBoxOverlay extends StatelessWidget {
  final List<DetectionObject> detections;
  final Widget child;
  final bool mirrorHorizontal;

  const BoundingBoxOverlay({
    super.key,
    required this.detections,
    required this.child,
    this.mirrorHorizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: CustomPaint(
            painter: BoundingBoxPainter(
              detections: detections,
              mirrorHorizontal: mirrorHorizontal,
            ),
          ),
        ),
      ],
    );
  }
}
