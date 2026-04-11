import 'package:camera/camera.dart';
import '../entities/detection_object.dart';
import '../repositories/detection_repository.dart';

class DetectionObjectFromFrame {
  final DetectionRepository _repository;
  DetectionObjectFromFrame(this._repository);

  Future<List<DetectionObject>> call(
    CameraImage image, {
    required int rotationDegrees,
  }) =>
      _repository.detectFromFrame(
        image,
        rotationDegrees: rotationDegrees,
      );
}
