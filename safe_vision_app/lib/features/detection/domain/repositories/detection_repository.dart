import 'package:camera/camera.dart';
import '../entities/detection_object.dart';

abstract class DetectionRepository {
  Future<void> loadModel();

  Future<List<DetectionObject>> detectFromFrame(
    CameraImage image, {
    required int rotationDegrees,
  });

  Future<void> closeModel();
}
