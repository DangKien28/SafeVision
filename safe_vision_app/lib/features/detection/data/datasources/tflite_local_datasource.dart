import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../models/detected_object_model.dart';

// Lớp phụ trợ để tính toán thuật toán NMS cho YOLO
class _BoundingBox {
  final double left, top, right, bottom;
  _BoundingBox(this.left, this.top, this.right, this.bottom);
}

class TFLiteLocalDataSource {
  Interpreter? _interpreter;
  List<String> _labels = [];

  // CHUẨN CỦA MÔ HÌNH BẠN ĐÃ GỬI (640x640)
  static const int modelInputSize = 640; 
  static const int numClasses = 13; // 17 thuộc tính - 4 tọa độ
  static const int numAnchors = 8400; // Số ô vuông mà YOLO quét

  /// 1. Tải mô hình và nhãn vào bộ nhớ
  Future<void> initModel() async {
    try {
      // 1. Chỉ dùng Options mặc định (Bỏ XNNPackDelegate)
      final options = InterpreterOptions();

      // 2. CHÚ Ý SỬA ĐƯỜNG DẪN NÀY: Thêm chữ 'assets/' vào phía trước
      // Ở các phiên bản tflite_flutter mới, bạn phải ghi đường dẫn đầy đủ
      _interpreter = await Interpreter.fromAsset('assets/models/data_exported.tflite', options: options);

      final labelData = await rootBundle.loadString('assets/models/labels.txt');
      _labels = labelData.split('\n').where((label) => label.trim().isNotEmpty).toList();
      
      print('✅ Khởi tạo TFLite YOLOv8 thành công. Đã nạp ${_labels.length} nhãn.');
    } catch (e) {
      throw Exception('Lỗi khi khởi tạo TFLite Model: $e');
    }
  }

  /// 2. Xử lý khung hình và chạy nhận diện (YOLOv8 Logic)
  Future<List<DetectedObjectModel>> runInference(CameraImage cameraImage) async {
    if (_interpreter == null || _labels.isEmpty) {
      throw Exception('Model chưa được khởi tạo');
    }

    // A. Chuyển ảnh thành mảng Float32 (Từ 0.0 đến 1.0)
    final inputTensor = _convertCameraImageToTensor(cameraImage);

    // B. Chuẩn bị biến chứa Output của YOLOv8: Mảng [1][17][8400]
    var outputTensor = List.generate(
      1, (_) => List.generate(
        17, (_) => List.filled(numAnchors, 0.0)
      )
    );

    // C. Bơm ảnh vào AI
    _interpreter!.run(inputTensor, outputTensor);

    // D. Bóc tách dữ liệu YOLOv8 (Tọa độ X-Y ở giữa, W-H)
    List<_BoundingBox> boxes = [];
    List<double> scores = [];
    List<String> classes = [];

    // Lặp qua 8400 ô vuông
    for (int i = 0; i < numAnchors; i++) {
      double maxScore = 0;
      int classIndex = -1;

      // Tìm đồ vật có độ tin cậy cao nhất trong 13 class
      for (int c = 0; c < numClasses; c++) {
        double score = outputTensor[0][c + 4][i];
        if (score > maxScore) {
          maxScore = score;
          classIndex = c;
        }
      }

      // Ngưỡng tin cậy (Confidence Threshold): Chỉ lấy đồ vật > 50%
      if (maxScore > 0.50) {
        // Tọa độ của YOLOv8 là tọa độ tuyệt đối dựa trên ảnh 640x640
        // Ta cần chia cho 640 để đưa về chuẩn 0.0 -> 1.0 cho giao diện dễ vẽ
        double cx = outputTensor[0][0][i] / modelInputSize;
        double cy = outputTensor[0][1][i] / modelInputSize;
        double w = outputTensor[0][2][i] / modelInputSize;
        double h = outputTensor[0][3][i] / modelInputSize;

        // Chuyển đổi Tâm X, Y thành Tọa độ 4 góc
        double left = cx - (w / 2);
        double top = cy - (h / 2);
        double right = cx + (w / 2);
        double bottom = cy + (h / 2);
        
        boxes.add(_BoundingBox(left, top, right, bottom));
        scores.add(maxScore);
        
        String label = _labels.length > classIndex ? _labels[classIndex] : 'Unknown';
        classes.add(label);
      }
    }

    // E. Lọc các khung hình trùng lặp (Non-Maximum Suppression)
    return _applyNMS(boxes, scores, classes, 0.45); // Ngưỡng IoU là 45%
  }

  /// 3. Hàm phụ trợ: Lọc khung hình trùng lặp (Thuật toán NMS)
  List<DetectedObjectModel> _applyNMS(
    List<_BoundingBox> boxes, 
    List<double> scores, 
    List<String> classes, 
    double iouThreshold
  ) {
    List<DetectedObjectModel> result = [];
    
    // Sắp xếp các ô vuông theo độ tin cậy giảm dần
    List<int> indices = List.generate(scores.length, (i) => i);
    indices.sort((a, b) => scores[b].compareTo(scores[a]));

    while (indices.isNotEmpty) {
      int current = indices.removeAt(0);
      _BoundingBox currentBox = boxes[current];
      
      result.add(DetectedObjectModel(
        label: classes[current],
        confidence: scores[current],
        left: currentBox.left,
        top: currentBox.top,
        right: currentBox.right,
        bottom: currentBox.bottom,
      ));

      // Loại bỏ các ô vuông khác đè lên ô vuông hiện tại quá nhiều
      indices.removeWhere((idx) {
        _BoundingBox otherBox = boxes[idx];
        double iou = _calculateIoU(currentBox, otherBox);
        return iou > iouThreshold;
      });
    }
    return result;
  }

  // Tính tỷ lệ đè lên nhau (Intersection over Union)
  double _calculateIoU(_BoundingBox a, _BoundingBox b) {
    double intersectionLeft = math.max(a.left, b.left);
    double intersectionTop = math.max(a.top, b.top);
    double intersectionRight = math.min(a.right, b.right);
    double intersectionBottom = math.min(a.bottom, b.bottom);

    if (intersectionRight < intersectionLeft || intersectionBottom < intersectionTop) return 0.0;

    double intersectionArea = (intersectionRight - intersectionLeft) * (intersectionBottom - intersectionTop);
    double areaA = (a.right - a.left) * (a.bottom - a.top);
    double areaB = (b.right - b.left) * (b.bottom - b.top);

    return intersectionArea / (areaA + areaB - intersectionArea);
  }

/// 4. Hàm phụ trợ: Chuyển Camera thành Mảng Float32 (4 CHIỀU)
  // Đã sửa kiểu trả về thêm 1 cấp List nữa (Thành 4 chiều)
  List<List<List<List<double>>>> _convertCameraImageToTensor(CameraImage image) {
    img.Image? decodedImage;

    if (image.format.group == ImageFormatGroup.yuv420) {
      decodedImage = _convertYUV420ToImage(image);
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      decodedImage = _convertBGRA8888ToImage(image);
    }

    if (decodedImage == null) {
      throw Exception('Không hỗ trợ định dạng camera này');
    }

    img.Image resizedImage = img.copyResize(decodedImage, width: modelInputSize, height: modelInputSize);

    // THAY ĐỔI QUAN TRỌNG: Bọc toàn bộ mảng trong một dấu ngoặc vuông [ ]
    // Điều này tạo ra chiều (dimension) đầu tiên có giá trị là 1 (Batch size = 1)
    return [
      List.generate(
        modelInputSize,
        (y) => List.generate(
          modelInputSize,
          (x) {
            final pixel = resizedImage.getPixel(x, y);
            // Chia cho 255.0 để đưa về chuẩn 0.0 -> 1.0
            return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
          },
        ),
      )
    ]; // Đóng ngoặc vuông của mảng 4 chiều
  }

  img.Image _convertYUV420ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;
    final uvRowStride = cameraImage.planes[1].bytesPerRow;
    final uvPixelStride = cameraImage.planes[1].bytesPerPixel!;
    final image = img.Image(width: width, height: height);

    for (var w = 0; w < width; w++) {
      for (var h = 0; h < height; h++) {
        final uvIndex = uvPixelStride * (w / 2).floor() + uvRowStride * (h / 2).floor();
        final index = h * cameraImage.planes[0].bytesPerRow + w;

        final y = cameraImage.planes[0].bytes[index];
        final u = cameraImage.planes[1].bytes[uvIndex];
        final v = cameraImage.planes[2].bytes[uvIndex];

        int r = (y + 1.402 * (v - 128)).round().clamp(0, 255);
        int g = (y - 0.344136 * (u - 128) - 0.714136 * (v - 128)).round().clamp(0, 255);
        int b = (y + 1.772 * (u - 128)).round().clamp(0, 255);

        image.setPixelRgb(w, h, r, g, b);
      }
    }
    return image;
  }

  img.Image _convertBGRA8888ToImage(CameraImage cameraImage) {
    return img.Image.fromBytes(
      width: cameraImage.width,
      height: cameraImage.height,
      bytes: cameraImage.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }

  void dispose() {
    _interpreter?.close();
  }
}