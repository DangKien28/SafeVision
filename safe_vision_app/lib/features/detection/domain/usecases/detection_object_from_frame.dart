import '../../../../core/models/camera_frame.dart';
import '../entities/detection_object.dart';
import '../repositories/detection_repository.dart';
 
/// Runs inference on a single camera frame and returns detected objects.
///
/// Does NOT implement [UseCase] because it requires two parameters
/// ([CameraFrame] + [rotationDegrees]).  Called directly from [DetectionBloc].
class DetectionObjectFromFrame {
  DetectionObjectFromFrame(this._repository);
  final DetectionRepository _repository;
 
  Future<List<DetectionObject>> call(
    CameraFrame frame, {
    required int rotationDegrees,
  }) =>
      _repository.detectFromFrame(frame, rotationDegrees: rotationDegrees);
}
