import 'package:safe_vision_app/features/detection/data/datasources/detection_local_datasource.dart';
import 'package:safe_vision_app/features/detection/domain/entities/bounding_box_entity.dart';
import 'package:safe_vision_app/features/detection/domain/repositories/detection_repository.dart';

class DetectionRepositoryImpl implements DetectionRepository {
  final DetectionLocalDatasource datasource;

  DetectionRepositoryImpl(this.datasource);

  @override
  Future<List<BoundingBoxEntity>> detect(List<int> imageBytes) async {
    final models = await datasource.detect(imageBytes);

    // 🔁 Model → Entity
    return models.map((m) => m.toEntity()).toList();
  }
}
