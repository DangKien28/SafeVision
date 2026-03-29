import '../../domain/entities/detection_object.dart';

class BoundingBoxModel {
  final double left;
  final double top;
  final double width;
  final double height;

  const BoundingBoxModel({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Từ Map (JSON)
  factory BoundingBoxModel.fromMap(Map<String, dynamic> map) {
    return BoundingBoxModel(
      left: (map['left'] as num).toDouble(),
      top: (map['top'] as num).toDouble(),
      width: (map['width'] as num).toDouble(),
      height: (map['height'] as num).toDouble(),
    );
  }

  /// Từ TFLite output: [top, left, bottom, right] normalized
  factory BoundingBoxModel.fromTFLiteList(List<dynamic> list) {
    final top = (list[0] as num).toDouble();
    final left = (list[1] as num).toDouble();
    final bottom = (list[2] as num).toDouble();
    final right = (list[3] as num).toDouble();
    return BoundingBoxModel(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }

  BoundingBox toEntity() => BoundingBox(
        left: left,
        top: top,
        width: width,
        height: height,
      );
}
