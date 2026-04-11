

import '../../../../core/services/camera_service.dart' show CameraFrame;

abstract class DetectionLocalDatasource {
  Future<void> loadModel();
  Future<List<Map<String, dynamic>>> runInference(
    CameraFrame frame, {
    required int rotationDegrees,
  });
  Future<void> closeModel();
}