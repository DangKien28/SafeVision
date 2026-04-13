import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/presentation/widgets/accessible_button.dart';
import '../bloc/detection_bloc.dart';
import '../widgets/bounding_box_painter.dart';

class DetectionPage extends StatefulWidget {
  const DetectionPage({Key? key}) : super(key: key);

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  CameraController? _cameraController;
  bool _hasPermission = false;
  bool _isCameraInitialized = false;
  
  // Biến này đóng vai trò như một cái "van", ngăn luồng camera đẩy 30 ảnh/giây vào AI
  bool _isProcessingFrame = false; 

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermission();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // Xin quyền Camera
  Future<void> _checkAndRequestPermission() async {
    var status = await Permission.camera.request();
    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
      });
      await _initializeCamera();
    } else {
      print("Người dùng đã từ chối quyền Camera");
    }
  }

  // Khởi tạo Camera và Bật luồng quét
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _cameraController = CameraController(
        cameras.first, // Thường là camera sau
        ResolutionPreset.medium, // Medium để tiết kiệm pin và tối ưu cho AI
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });

        // ----- BẮT ĐẦU LUỒNG QUÉT LIÊN TỤC -----
        _cameraController!.startImageStream((CameraImage image) async {
          // Nếu hệ thống đang xử lý dở bức ảnh trước, thì bỏ qua bức ảnh này
          if (_isProcessingFrame) return;

          _isProcessingFrame = true; // Đóng van
          
          // Gửi ảnh vào BLoC để AI và TTS xử lý
          context.read<DetectionBloc>().add(ProcessCameraFrameEvent(image));

          // Đợi 300ms (tương đương khoảng 3 khung hình/giây) rồi mới mở van tiếp
          // Điều này giúp máy không bị nóng và AI không bị quá tải
          await Future.delayed(const Duration(milliseconds: 300));
          
          _isProcessingFrame = false; // Mở van
        });
      }
    } catch (e) {
      print("Lỗi khởi tạo camera: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Đang xin quyền máy ảnh...',
            style: TextStyle(color: Colors.yellowAccent, fontSize: 24),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              // ----- PHẦN TRÊN: CAMERA (Chiếm 70%) -----
              Expanded(
                flex: 7,
                child: _isCameraInitialized && _cameraController != null
                    ? AccessibleButton(
                        backgroundColor: Colors.transparent, 
                        borderColor: Colors.yellowAccent,
                        semanticLabel: 'Khu vực máy ảnh đang hoạt động.',
                        semanticHint: 'Hệ thống đang tự động quét.',
                        onTap: () {
                          // Người dùng khiếm thị có thể bấm vào đây để ép máy quét ngay
                          print('Bấm vào vùng camera');
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12.0),
                          child: SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            // Dùng Stack để đè Khung Bounding Box lên trên luồng Camera
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Lớp 1: Luồng Camera thực tế
                                CameraPreview(_cameraController!),
                                
                                // Lớp 2: Vẽ Khung màu vàng lên các vật thể tìm thấy
                                BlocBuilder<DetectionBloc, DetectionState>(
                                  builder: (context, state) {
                                    if (state is DetectionRunning && state.objects.isNotEmpty) {
                                      return CustomPaint(
                                        painter: BoundingBoxPainter(state.objects),
                                      );
                                    }
                                    return const SizedBox.shrink(); // Không vẽ gì nếu không thấy
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.yellowAccent),
                      ),
              ),

              // ----- PHẦN DƯỚI: TÌM ĐỒ VẬT (Chiếm 30%) -----
              Expanded(
                flex: 3,
                child: AccessibleButton(
                  borderColor: Colors.greenAccent,
                  semanticLabel: 'Tìm đồ vật cụ thể.',
                  semanticHint: 'Chạm hai lần để mở danh sách đồ vật.',
                  onTap: () {
                    // Chức năng này sẽ làm ở các bước sau
                    print('Mở chức năng tìm đồ vật...');
                  },
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 50, color: Colors.greenAccent),
                      SizedBox(height: 8),
                      Text(
                        'TÌM ĐỒ VẬT',
                        style: TextStyle(
                          fontSize: 28, 
                          fontWeight: FontWeight.bold, 
                          color: Colors.greenAccent
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}