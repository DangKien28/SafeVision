import 'package:camera/camera.dart';
import '../entities/detected_object.dart';
import '../repositories/detection_repository.dart';

class DetectObjectUseCase {
  final DetectionRepository repository;

  DetectObjectUseCase(this.repository);

  /// Nhận vào một khung hình Camera và trả về danh sách vật thể
  Future<List<DetectedObject>> execute(CameraImage frame) async {
    // Gọi xuống Repository để xử lý
    // Ở đây bạn có thể thêm các logic kiểm tra, ví dụ: 
    // nếu frame quá tối, trả về mảng rỗng trước khi đẩy vào AI (nếu cần)
    
    return await repository.processCameraFrame(frame);
  }
}