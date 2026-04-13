import 'package:camera/camera.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detected_object.dart';
import '../../domain/usecases/detect_object_usecase.dart';
import '../../../tts/domain/usecases/speak_text_usecase.dart';

// --- EVENTS ---
abstract class DetectionEvent {}

class ProcessCameraFrameEvent extends DetectionEvent {
  final CameraImage frame;
  ProcessCameraFrameEvent(this.frame);
}

// --- STATES ---
abstract class DetectionState {}

class DetectionInitial extends DetectionState {}
class DetectionRunning extends DetectionState {
  final List<DetectedObject> objects; // Danh sách vật thể để vẽ lên màn hình
  DetectionRunning(this.objects);
}

// --- BLOC ---
class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final DetectObjectUseCase detectObjectUseCase;
  final SpeakTextUseCase speakTextUseCase;

  // Bản đồ lưu trữ thời gian đọc cuối cùng của từng vật thể
  final Map<String, DateTime> _lastSpokenTimes = {};
  // Thời gian chờ (giây) trước khi đọc lại cùng một vật thể
  final int _debounceSeconds = 4;

  DetectionBloc({
    required this.detectObjectUseCase,
    required this.speakTextUseCase,
  }) : super(DetectionInitial()) {
    
    // Sử dụng on<Event> bình thường. 
    // Việc kiểm soát tốc độ khung hình (FPS) ta sẽ làm ở UI để tránh Bloc bị quá tải.
    on<ProcessCameraFrameEvent>((event, emit) async {
      try {
        // 1. Gọi AI xử lý khung hình
        final detectedObjects = await detectObjectUseCase.execute(event.frame);
        
        // 2. Cập nhật UI để vẽ Bounding Box ngay lập tức
        emit(DetectionRunning(detectedObjects));

        // 3. Xử lý âm thanh (Debounce)
        _handleTTSFeedback(detectedObjects);

      } catch (e) {
        print("Lỗi nhận diện frame: $e");
      }
    });
  }

  void _handleTTSFeedback(List<DetectedObject> objects) {
    if (objects.isEmpty) return;

    final now = DateTime.now();

    // Duyệt qua các vật thể tìm thấy (Ưu tiên vật có độ tin cậy cao nhất)
    objects.sort((a, b) => b.confidence.compareTo(a.confidence));

    for (var obj in objects) {
      final lastSpoken = _lastSpokenTimes[obj.label];

      // Nếu chưa từng đọc, HOẶC đã qua thời gian debounce
      if (lastSpoken == null || now.difference(lastSpoken).inSeconds > _debounceSeconds) {
        
        // Phát âm thanh
        speakTextUseCase.execute(obj.label);
        
        // Cập nhật lại thời gian vừa đọc
        _lastSpokenTimes[obj.label] = now;
        
        // Chỉ đọc 1 vật thể nổi bật nhất trong mỗi khung hình để tránh tiếng nói đè nhau
        break; 
      }
    }
  }
}