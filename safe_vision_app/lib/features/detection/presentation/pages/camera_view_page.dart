import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart'; // Import thư viện mới
import '../../../tts/data/datasources/tts_service.dart';

class CameraViewPage extends StatefulWidget {
  const CameraViewPage({super.key});

  @override
  State<CameraViewPage> createState() => _CameraViewPageState();
}

class _CameraViewPageState extends State<CameraViewPage> {
  final TtsService _ttsService = TtsService();
  
  // --- BIẾN KHỞI TẠO CAMERA ---
  CameraController? _controller; 
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _setupCameraAndSystem(); // Gộp khởi tạo camera và TTS
  }

  /// Bước 2: Khởi tạo CameraController
  Future<void> _setupCameraAndSystem() async {
    try {
      // 1. Lấy danh sách camera có sẵn trên thiết bị
      _cameras = await availableCameras();
      
      if (_cameras != null && _cameras!.isNotEmpty) {
        // 2. Khởi tạo controller với camera sau (index 0) và độ phân giải trung bình
        _controller = CameraController(
          _cameras![0], 
          ResolutionPreset.medium,
          enableAudio: false, // Tắt audio camera để không xung đột với TTS
        );

        // 3. Lệnh quan trọng: Kích hoạt ống kính
        await _controller!.initialize();
        
        if (!mounted) return;
        setState(() {
          _isCameraInitialized = true;
        });
      }

      // 4. Khởi tạo TTS và chào mừng (Như Sprint 1)
      await _ttsService.initTts();
      await Future.delayed(const Duration(seconds: 1));
      await _ttsService.speak("Hệ thống camera đã sẵn sàng.");
      HapticFeedback.mediumImpact();
      
    } catch (e) {
      debugPrint("Lỗi khởi tạo: $e");
    }
  }

  void _handleDetectionRequest() async {
    await HapticFeedback.vibrate(); 
    await _ttsService.speak("Đang nhận diện vật thể");
    debugPrint("Lệnh nhận diện kích hoạt trên Camera thật.");
  }

  @override
  void dispose() {
    _controller?.dispose(); // Giải phóng camera khi thoát app
    _ttsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _handleDetectionRequest,
        child: Stack(
          children: [
            // Bước 3: Thay thế Text bằng CameraPreview
            _buildCameraDisplay(),
            _buildDetectionButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraDisplay() {
    // Nếu camera chưa load xong, hiện vòng xoay tải
    if (!_isCameraInitialized || _controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.yellow));
    }
    
    // Hiển thị luồng hình ảnh thật từ ống kính
    return Center(
      child: CameraPreview(_controller!),
    );
  }

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
            child: const Text('QUÉT VẬT THỂ', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}