import '../../../../core/models/camera_frame.dart';

abstract class DetectionLocalDatasource {
  Future<void> loadModel();
  Future<List<Map<String, dynamic>>> runInference(
    CameraFrame frame, {
    required int rotationDegrees,
  });
  Future<void> closeModel();
}
