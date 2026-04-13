import 'package:camera/camera.dart';

import '../../domain/entities/detected_object.dart';
import '../../domain/repositories/detection_repository.dart';
import '../datasources/tflite_local_datasource.dart';

class DetectionRepositoryImpl implements DetectionRepository {
  final TFLiteLocalDataSource dataSource;

  DetectionRepositoryImpl({required this.dataSource});

  @override
  Future<void> initializeModel() async {
    await dataSource.initModel();
  }

  @override
  Future<List<DetectedObject>> processCameraFrame(CameraImage frame) async {
    try {
      // Lấy dữ liệu model từ data source
      final modelList = await dataSource.runInference(frame);
      
      // Chuyển đổi Data Model sang Domain Entity (Clean Architecture)
      return modelList.map((model) => DetectedObject(
        label: model.label,
        confidence: model.confidence,
        top: model.top,
        left: model.left,
        bottom: model.bottom,
        right: model.right,
      )).toList();

    } catch (e) {
      // Trong thực tế có thể quăng ra các Exception tùy chỉnh
      print("Lỗi Repository khi xử lý frame: $e");
      return [];
    }
  }

  @override
  void dispose() {
    dataSource.dispose();
  }
}