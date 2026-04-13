import 'package:flutter/material.dart';
import '../../domain/entities/detected_object.dart';

class BoundingBoxPainter extends CustomPainter {
  final List<DetectedObject> objects;

  BoundingBoxPainter(this.objects);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textStyle = const TextStyle(
      color: Colors.black,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );

    for (var obj in objects) {
      // Chuyển đổi tọa độ chuẩn hóa thành pixel thực tế trên màn hình
      final rect = Rect.fromLTRB(
        obj.left * size.width,
        obj.top * size.height,
        obj.right * size.width,
        obj.bottom * size.height,
      );

      // Vẽ khung vuông
      canvas.drawRect(rect, paint);

      // Vẽ nền cho Text để dễ đọc
      final textSpan = TextSpan(
        text: '${obj.label} ${(obj.confidence * 100).toStringAsFixed(0)}%',
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Vẽ khung nền đen cho Text
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top - 24, textPainter.width + 8, 24),
        Paint()..color = Colors.yellowAccent,
      );
      
      // Vẽ Text
      textPainter.paint(canvas, Offset(rect.left + 4, rect.top - 22));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    // Vẽ lại khi danh sách vật thể thay đổi
    return oldDelegate.objects != objects;
  }
}