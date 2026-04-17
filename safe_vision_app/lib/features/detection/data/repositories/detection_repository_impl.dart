import '../../../../core/models/camera_frame.dart';
import '../../domain/entities/detection_object.dart';
import '../../domain/repositories/detection_repository.dart';
import '../datasources/detection_local_datasource.dart';
import '../models/bounding_box_model.dart';

/// Concrete implementation that delegates to [DetectionLocalDatasource] and
/// converts the raw inference maps into domain [DetectionObject] instances.
class DetectionRepositoryImpl implements DetectionRepository {
  DetectionRepositoryImpl(this._datasource);

  final DetectionLocalDatasource _datasource;

  @override
  Future<void> loadModel() => _datasource.loadModel();

  @override
  Future<void> closeModel() => _datasource.closeModel();

  @override
  Future<List<DetectionObject>> detectFromFrame(
    CameraFrame frame, {
    required int rotationDegrees,
  }) async {
    final rawList = await _datasource.runInference(
      frame,
      rotationDegrees: rotationDegrees,
    );

    return rawList.map((map) {
      final box = BoundingBoxModel.fromMap(map);
      return DetectionObject(
        label: map['label'] as String,
        confidence: (map['confidence'] as num).toDouble(),
        boundingBox: box.toEntity(),
      );
    }).toList();
  }
}