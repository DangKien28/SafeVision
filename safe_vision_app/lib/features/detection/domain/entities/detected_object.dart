/// Đại diện cho một vật thể đã được nhận diện thành công
class DetectedObject {
  final String label;         // Tên vật thể (VD: "Cái bàn", "Người")
  final double confidence;    // Độ tin cậy (VD: 0.85 tương đương 85%)
  
  // Tọa độ khung vuông (Bounding Box)
  // Các giá trị này nằm trong khoảng từ 0.0 đến 1.0
  final double top;
  final double left;
  final double bottom;
  final double right;

  DetectedObject({
    required this.label,
    required this.confidence,
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });
}