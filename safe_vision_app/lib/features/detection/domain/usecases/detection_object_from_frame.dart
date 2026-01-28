import '../entities/bounding_box_entity.dart';
import '../repositories/detection_repository.dart';

class DetectFromFrameUsecase {
  final DetectionRepository repository;

  DetectFromFrameUsecase(this.repository);

  Future<List<BoundingBoxEntity>> call(List<int> imageBytes) {
    return repository.detect(imageBytes);
  }
}
