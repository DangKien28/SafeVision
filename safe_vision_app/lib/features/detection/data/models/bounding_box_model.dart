import '../../domain/entities/bounding_box_entity.dart';

class BoundingBoxModel {
  final String label;
  final double confidence;
  final int x1;
  final int y1;
  final int x2;
  final int y2;

  BoundingBoxModel({
    required this.label,
    required this.confidence,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  /// 🔥 BẮT BUỘC CÓ
  factory BoundingBoxModel.fromJson(Map<String, dynamic> json) {
    return BoundingBoxModel(
      label: json['label'],
      confidence: (json['confidence'] as num).toDouble(),
      x1: json['x1'],
      y1: json['y1'],
      x2: json['x2'],
      y2: json['y2'],
    );
  }

  BoundingBoxEntity toEntity() {
    return BoundingBoxEntity(
      label: label,
      confidence: confidence,
      x1: x1.toDouble(),
      y1: y1.toDouble(),
      x2: x2.toDouble(),
      y2: y2.toDouble(),
    );
  }
}
