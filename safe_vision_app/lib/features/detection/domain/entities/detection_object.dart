import '../repositories/detection_repository.dart';

class DetectObjectsUseCase {
  final DetectionRepository repository;
  DetectObjectsUseCase(this.repository);

  Future call(List<int> imageBytes) {
    return repository.detect(imageBytes);
  }
}
