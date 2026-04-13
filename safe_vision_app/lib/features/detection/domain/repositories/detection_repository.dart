import 'package:camera/camera.dart';
import '../entities/detected_object.dart';

/// Bản hợp đồng định nghĩa các thao tác nhận diện vật thể
abstract class DetectionRepository {
  /// Khởi tạo và nạp mô hình AI vào bộ nhớ
  Future<void> initializeModel();

  /// Phân tích một khung hình từ camera và trả về danh sách vật thể tìm thấy
  Future<List<DetectedObject>> processCameraFrame(CameraImage frame);

  /// Giải phóng bộ nhớ khi không dùng nữa
  void dispose();
}