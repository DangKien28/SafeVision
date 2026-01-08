import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../tts/data/datasources/tts_service.dart';

/// Trang hiển thị Camera và xử lý tương tác đa giác quan (Thính giác - Xúc giác).
/// Thiết kế tối ưu cho người khiếm thị với độ tương phản cao và phản hồi tức thì.
class CameraViewPage extends StatefulWidget {
  const CameraViewPage({super.key});

  @override
  State<CameraViewPage> createState() => _CameraViewPageState();
}

class _CameraViewPageState extends State<CameraViewPage> {
  // Service quản lý giọng nói tiếng Việt
  final TtsService _ttsService = TtsService();

  @override
  void initState() {
    super.initState();
    // Task 26: Khởi chạy hệ thống tự động ngay khi vào trang
    _initializeSystem(); 
  }

  // --- LOGIC HỆ THỐNG ---

  /// Khởi tạo TTS và phát lời chào mừng kèm rung nhẹ báo hiệu sẵn sàng.
  Future<void> _initializeSystem() async {
    try {
      await _ttsService.initTts();
      
      // Delay 2 giây để đảm bảo Engine TTS đã Bound hoàn toàn trên Android
      await Future.delayed(const Duration(seconds: 1)); 

      await _ttsService.speak(
        "Chào mừng bạn đến với Safe Vision. Hệ thống đã sẵn sàng. Chạm vào màn hình để quét."
      );
      
      HapticFeedback.mediumImpact(); 
    } catch (e) {
      debugPrint("LOG: Lỗi khởi tạo: $e");
    }
  }

  // --- LOGIC PHẢN HỒI XÚC GIÁC (RUNG) ---

  /// Rung 1 phát ngắn: Xác nhận đã nhận lệnh từ người dùng.
  Future<void> _vibrateReceived() async {
    await HapticFeedback.vibrate(); 
  }

  /// Rung 2 phát dài: Thông báo nhận diện thành công (Dùng cho Sprint 2).
  Future<void> _vibrateSuccess() async {
    for (int i = 0; i < 2; i++) {
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 400)); 
    }
  }

  /// Rung dồn dập: Cảnh báo nguy hiểm/Vật cản (Dùng cho Sprint 2).
  Future<void> _vibrateWarning() async {
    for (int i = 0; i < 6; i++) {
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 100)); 
    }
  }

  // --- XỬ LÝ SỰ KIỆN ---

  /// Xử lý khi người dùng chạm vào màn hình hoặc nút bấm.
  void _handleDetectionRequest() async {
    // 1. Phản hồi rung ngắn báo nhận lệnh
    await _vibrateReceived(); 
    
    // 2. Thông báo bằng giọng nói
    await _ttsService.speak("Đang nhận diện vật thể, vui lòng đợi");
    
    debugPrint("Hệ thống: Lệnh nhận diện SAF-24/25 đã thực thi.");
  }

  @override
  void dispose() {
    _ttsService.stop(); // Giải phóng tài nguyên khi đóng trang
    super.dispose();
  }

  // --- GIAO DIỆN (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Nền đen tương phản cực cao
      body: GestureDetector(
        onTap: _handleDetectionRequest, // Chạm bất kỳ đâu cũng kích hoạt lệnh
        child: Stack(
          children: [
            _buildCameraPlaceholder(),
            _buildDetectionButton(),
          ],
        ),
      ),
    );
  }

  /// Khung hiển thị Camera (Sẽ thay thế bằng CameraController ở Sprint 2).
  Widget _buildCameraPlaceholder() {
    return const Center(
      child: Text(
        "CAMERA PREVIEW", 
        style: TextStyle(
          color: Colors.white, 
          letterSpacing: 4, 
          fontWeight: FontWeight.w300
        )
      )
    );
  }

  /// Nút bấm khổng lồ màu vàng phía dưới (SAF-24).
  Widget _buildDetectionButton() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(25, 0, 25, 40),
        child: SizedBox(
          width: double.infinity,
          height: 90, 
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.yellow, 
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 10,
            ),
            onPressed: _handleDetectionRequest,
            child: const Text(
              'QUÉT VẬT THỂ',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)
            ),
          ),
        ),
      ),
    );
  }
}