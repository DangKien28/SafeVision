import '../entities/bounding_box_entity.dart';

abstract class DetectionRepository {
  Future<List<BoundingBoxEntity>> detect(List<int> imageBytes);
}
