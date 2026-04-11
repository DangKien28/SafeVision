

import '../../../../core/services/camera_service.dart' show CameraFrame;
import '../entities/detection_object.dart';
import '../repositories/detection_repository.dart';

class DetectionObjectFromFrame {
  final DetectionRepository _repository;
  DetectionObjectFromFrame(this._repository);

  Future<List<DetectionObject>> call(
    CameraFrame frame, {
    required int rotationDegrees,
  }) =>
      _repository.detectFromFrame(frame, rotationDegrees: rotationDegrees);
}