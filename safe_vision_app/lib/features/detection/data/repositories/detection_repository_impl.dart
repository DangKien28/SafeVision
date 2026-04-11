import 'package:camera/camera.dart';
import '../../domain/entities/detection_object.dart';
import '../../domain/repositories/detection_repository.dart';
import '../datasources/detection_local_datasource.dart';

class DetectionRepositoryImpl implements DetectionRepository {
  final DetectionLocalDatasource _datasource;

  DetectionRepositoryImpl(this._datasource);

  @override
  Future<void> loadModel() => _datasource.loadModel();

  @override
  Future<List<DetectionObject>> detectFromFrame(
    CameraImage image, {
    required int rotationDegrees,
  }) async {
    final rawList = await _datasource.runInference(
      image,
      rotationDegrees: rotationDegrees,
    );
    return rawList
        .map((map) => DetectionObject(
              label: map['label'] as String,
              confidence: (map['confidence'] as num).toDouble(),
              boundingBox: BoundingBox(
                left: (map['left'] as num).toDouble(),
                top: (map['top'] as num).toDouble(),
                width: (map['width'] as num).toDouble(),
                height: (map['height'] as num).toDouble(),
              ),
            ))
        .toList();
  }

  @override
  Future<void> closeModel() => _datasource.closeModel();
}
