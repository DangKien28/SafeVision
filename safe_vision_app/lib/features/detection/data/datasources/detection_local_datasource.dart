import 'package:camera/camera.dart';

abstract class DetectionLocalDatasource {
  Future<void> loadModel();
  Future<List<Map<String, dynamic>>> runInference(CameraImage image);
  Future<void> closeModel();
}
