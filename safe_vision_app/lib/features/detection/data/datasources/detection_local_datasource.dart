import '../models/bounding_box_model.dart';

abstract class DetectionLocalDatasource {
  Future<List<BoundingBoxModel>> detect(List<int> imageBytes);
}
