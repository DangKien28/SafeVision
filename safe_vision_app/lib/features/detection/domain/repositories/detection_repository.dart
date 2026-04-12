import '../../../../core/services/camera_service.dart' show CameraFrame;
import '../entities/detection_object.dart';

abstract class DetectionRepository {
  Future<void> loadModel();
  Future<List<DetectionObject>> detectFromFrame(
    CameraFrame frame, {
    required int rotationDegrees,
  });
  Future<void> closeModel();
}
