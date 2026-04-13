import '../../../../core/models/camera_frame.dart';
import '../entities/detection_object.dart';

abstract class DetectionRepository {
  Future<void> loadModel();
  Future<List<DetectionObject>> detectFromFrame(
    CameraFrame frame, {
    required int rotationDegrees,
  });
  Future<void> closeModel();
}
