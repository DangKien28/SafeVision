import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'package:safe_vision_app/features/detection/domain/entities/bounding_box_entity.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/bounding_box_painter.dart';

class CameraViewPage extends StatefulWidget {
  const CameraViewPage({super.key});

  @override
  State<CameraViewPage> createState() => _CameraViewPageState();
}

class _CameraViewPageState extends State<CameraViewPage> {
  CameraController? _cameraController;
  bool _isDetecting = false;

  Size? _imageSize; // size ảnh gửi AI
  List<BoundingBoxEntity> _boxes = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  // =========================
  // INIT CAMERA
  // =========================
  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );

    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _cameraController!.initialize();

    // Tắt flash cho chắc
    await _cameraController!.setFlashMode(FlashMode.off);

    // Bắt đầu stream
    await _cameraController!.startImageStream((CameraImage image) {
      _processCameraImage(image);
    });

    setState(() {});
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      // 1. Convert YUV420 → RGB
      final img.Image converted = _convertYUV420(image);

      // 2. Resize cho AI
      final resized = img.copyResize(converted, width: 640);

      _imageSize = Size(resized.width.toDouble(), resized.height.toDouble());

      // 3. Encode JPEG
      final jpegBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 70));

      // 4. Gửi AI
      final response = await http.post(
        Uri.parse('http://192.168.86.246:5000/detect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Encode(jpegBytes)}),
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _boxes = data.map((e) => BoundingBoxEntity.fromJson(e)).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Stream detect error: $e');
    }

    _isDetecting = false;
  }

  img.Image _convertYUV420(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    final img.Image imgImage = img.Image(width: width, height: height);

    final Plane planeY = image.planes[0];
    final Plane planeU = image.planes[1];
    final Plane planeV = image.planes[2];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int indexY = y * planeY.bytesPerRow + x;
        final int uvIndex = (y ~/ 2) * planeU.bytesPerRow + (x ~/ 2);

        final int yValue = planeY.bytes[indexY];
        final int uValue = planeU.bytes[uvIndex];
        final int vValue = planeV.bytes[uvIndex];

        int r = (yValue + 1.370705 * (vValue - 128)).round();
        int g = (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128))
            .round();
        int b = (yValue + 1.732446 * (uValue - 128)).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        imgImage.setPixelRgb(x, y, r, g, b);
      }
    }

    return imgImage;
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final camera = _cameraController!;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(camera),

          if (_imageSize != null)
            CustomPaint(
              painter: BoundingBoxPainter(
                boxes: _boxes,
                imageSize: _imageSize!,
              ),
            ),
        ],
      ),
    );
  }
}
