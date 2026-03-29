import 'package:camera/camera.dart';
import '../entities/detection_object.dart';

abstract class DetectionRepository {
  /// Tải model TFLite vào bộ nhớ
  Future<void> loadModel();

  /// Chạy inference trên một frame camera
  Future<List<DetectionObject>> detectFromFrame(CameraImage image);

  /// Giải phóng tài nguyên model
  Future<void> closeModel();
}