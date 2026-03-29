import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../error/exceptions.dart' as ex;

/// Chuyển đổi CameraImage (YUV420 / BGRA8888) → img.Image → Float32List cho TFLite
class ImageConverter {
  ImageConverter._();

  /// Chuyển CameraImage sang img.Image (RGB)
  static img.Image convertCameraImage(CameraImage cameraImage) {
    try {
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888(cameraImage);
      }
      throw ex.ImageConversionException(
        'Định dạng ảnh không hỗ trợ: ${cameraImage.format.group}',
      );
    } catch (e) {
      if (e is ex.ImageConversionException) rethrow;
      throw ex.ImageConversionException(e.toString());
    }
  }

  /// Resize + normalize về Float32List [1, inputSize, inputSize, 3]
  /// Giá trị pixel chuẩn hóa về [0.0, 1.0]
  static Float32List imageToFloat32(img.Image image, int inputSize) {
    final resized = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    final buffer = Float32List(1 * inputSize * inputSize * 3);
    int idx = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        buffer[idx++] = pixel.r / 255.0;
        buffer[idx++] = pixel.g / 255.0;
        buffer[idx++] = pixel.b / 255.0;
      }
    }
    return buffer;
  }

  // ── Private ───────────────────────────────────────────────

  static img.Image _convertYUV420(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    final yPlane = image.planes[0].bytes;
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;

    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final result = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * width + x;
        final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final int yVal = yPlane[yIndex];
        final int uVal = uPlane[uvIndex] - 128;
        final int vVal = vPlane[uvIndex] - 128;

        final int r = (yVal + 1.402 * vVal).round().clamp(0, 255);
        final int g =
            (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
        final int b = (yVal + 1.772 * uVal).round().clamp(0, 255);

        result.setPixelRgb(x, y, r, g, b);
      }
    }
    return result;
  }

  static img.Image _convertBGRA8888(CameraImage image) {
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }

  /// Dùng trong Isolate — nhận raw bytes thay vì CameraImage
  static img.Image convertFromRaw({
    required List<Uint8List> planeBytes,
    required List<int> planeRowStrides,
    required List<int> planePixelStrides,
    required int width,
    required int height,
  }) {
    final result = img.Image(width: width, height: height);

    final yPlane = planeBytes[0];
    final uPlane = planeBytes[1];
    final vPlane = planeBytes[2];
    final uvRowStride = planeRowStrides[1];
    final uvPixelStride = planePixelStrides[1];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * width + x;
        final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final yVal = yPlane[yIndex];
        final uVal = uPlane[uvIndex] - 128;
        final vVal = vPlane[uvIndex] - 128;

        final r = (yVal + 1.402 * vVal).round().clamp(0, 255);
        final g =
            (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
        final b = (yVal + 1.772 * uVal).round().clamp(0, 255);

        result.setPixelRgb(x, y, r, g, b);
      }
    }
    return result;
  }
}
