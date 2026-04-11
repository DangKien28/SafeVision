import 'package:camera/camera.dart';

abstract class DetectionLocalDatasource {
  Future<void> loadModel();
  Future<List<Map<String, dynamic>>> runInference(
    CameraImage image, {
    required int rotationDegrees,
  });
  Future<void> closeModel();
}
