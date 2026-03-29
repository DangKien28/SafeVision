import 'package:camera/camera.dart';
import '../entities/detection_object.dart';
import '../repositories/detection_repository.dart';

class DetectionObjectFromFrame {
  final DetectionRepository _repository;
  DetectionObjectFromFrame(this._repository);

  /// Chạy detection trên một CameraImage, trả về danh sách vật thể
  Future<List<DetectionObject>> call(CameraImage image) =>
      _repository.detectFromFrame(image);
}