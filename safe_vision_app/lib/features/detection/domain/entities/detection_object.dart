import 'package:equatable/equatable.dart';

class BoundingBox extends Equatable {
  final double left;
  final double top;
  final double width;
  final double height;

  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
  double get area => width * height;

  /// Vị trí ngang trong frame
  String get horizontalPosition {
    if (centerX < 0.33) return 'bên trái';
    if (centerX > 0.67) return 'bên phải';
    return 'phía trước';
  }

  /// Ước tính khoảng cách dựa trên diện tích bounding box
  String get proximityLabel {
    if (area > 0.25) return 'rất gần';
    if (area > 0.10) return 'gần';
    if (area > 0.03) return 'trung bình';
    return 'xa';
  }

  @override
  List<Object?> get props => [left, top, width, height];
}

class DetectionObject extends Equatable {
  final String label;
  final double confidence;
  final BoundingBox boundingBox;

  const DetectionObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  /// Câu cảnh báo giọng nói tự động
  String get voiceWarning {
    final pos = boundingBox.horizontalPosition;
    final dist = boundingBox.proximityLabel;
    return 'Phát hiện $label $pos, $dist';
  }

  /// Nguy hiểm nếu chiếm hơn 10% diện tích khung hình
  bool get isDangerous => boundingBox.area > 0.10;

  @override
  List<Object?> get props => [label, confidence, boundingBox];
}