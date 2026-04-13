class DetectedObjectModel {
  final String label;
  final double confidence;
  // Tọa độ chuẩn hóa (Normalized coordinates từ 0.0 đến 1.0)
  // Giúp UI dễ dàng vẽ khung (Bounding Box) bất kể kích thước màn hình
  final double top;
  final double left;
  final double bottom;
  final double right;

  DetectedObjectModel({
    required this.label,
    required this.confidence,
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });

  // Factory để tiện tạo object (nếu sau này cần mở rộng)
  factory DetectedObjectModel.fromMap(Map<String, dynamic> map) {
    return DetectedObjectModel(
      label: map['label'] as String,
      confidence: map['confidence'] as double,
      top: map['top'] as double,
      left: map['left'] as double,
      bottom: map['bottom'] as double,
      right: map['right'] as double,
    );
  }
}