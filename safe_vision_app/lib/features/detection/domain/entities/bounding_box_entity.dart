class BoundingBoxEntity {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String label;
  final double confidence;

  BoundingBoxEntity({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.label,
    required this.confidence,
  });

  /// 🔹 BỔ SUNG: Parse JSON từ Flask YOLO
  factory BoundingBoxEntity.fromJson(Map<String, dynamic> json) {
    return BoundingBoxEntity(
      x1: (json['x1'] as num).toDouble(),
      y1: (json['y1'] as num).toDouble(),
      x2: (json['x2'] as num).toDouble(),
      y2: (json['y2'] as num).toDouble(),
      label: json['label'] as String,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }
}
