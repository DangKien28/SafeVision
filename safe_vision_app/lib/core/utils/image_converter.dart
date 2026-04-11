import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Result of letterboxing: a ready-to-use input tensor plus metadata
/// for mapping model output coordinates back to the original frame.
class LetterboxResult {
  /// Float32 tensor in `[H x W x 3]` format with normalized `[0.0, 1.0]`
  /// values, RGB channel order, and NHWC layout without a batch dimension.
  final Float32List inputTensor;

  /// Scale factor applied to the original image.
  /// Model-space bounding boxes are divided by this value to recover original
  /// pixel coordinates.
  final double scale;

  /// Left padding in normalized `[0.0, 1.0]` coordinates.
  final double padLeft;

  /// Top padding in normalized `[0.0, 1.0]` coordinates.
  final double padTop;

  /// Image width after rotation is applied, not the raw sensor width.
  final int origWidth;

  /// Image height after rotation is applied.
  final int origHeight;

  const LetterboxResult({
    required this.inputTensor,
    required this.scale,
    required this.padLeft,
    required this.padTop,
    required this.origWidth,
    required this.origHeight,
  });
}

/// Converts camera image formats into YOLOv8 tensors and provides coordinate
/// utility helpers.
///
/// All methods are stateless and side-effect free, so they are safe to call
/// from any isolate without synchronization.
class ImageConverter {
  ImageConverter._();

  /// Converts raw YUV420 data from [CameraImage] into a Float32 tensor ready
  /// for YOLOv8 inference.
  ///
  /// Single-pass steps:
  /// 1. Rotate pixels using [rotationDegrees] (`0/90/180/270`).
  /// 2. Scale the rotated image down into an `[inputSize x inputSize]` box.
  /// 3. Pad the shorter side with `114/255` gray values.
  /// 4. Convert YUV to RGB and normalize to `[0.0, 1.0]`.
  ///
  /// [reuseBuffer] is optional and helps avoid per-frame GC allocations.
  /// If its size does not match, a new buffer is created.
  static LetterboxResult yuvToLetterboxedFloat32({
    required List<Uint8List> planes,
    required List<int> rowStrides,
    required List<int> pixelStrides,
    required int srcWidth,
    required int srcHeight,
    required int inputSize,
    required int rotationDegrees,
    Float32List? reuseBuffer,
  }) {
    // Image dimensions after rotation is applied.
    final bool swapDims = rotationDegrees == 90 || rotationDegrees == 270;
    final int rotW = swapDims ? srcHeight : srcWidth;
    final int rotH = swapDims ? srcWidth : srcHeight;

    // Letterbox scaling: fit the longest side into inputSize.
    final double scale = inputSize / (rotW > rotH ? rotW : rotH);
    final int scaledW = (rotW * scale).round().clamp(1, inputSize);
    final int scaledH = (rotH * scale).round().clamp(1, inputSize);
    final int padL = (inputSize - scaledW) ~/ 2;
    final int padT = (inputSize - scaledH) ~/ 2;

    final int tensorLen = inputSize * inputSize * 3;
    final Float32List tensor =
        (reuseBuffer != null && reuseBuffer.length == tensorLen)
            ? reuseBuffer
            : Float32List(tensorLen);

    final Uint8List yPlane = planes[0];
    final Uint8List uPlane = planes[1];
    final Uint8List vPlane = planes[2];
    final int yStride = rowStrides[0];
    final int uvStride = rowStrides[1];
    final int uvPixStride = pixelStrides[1];

    // Planar format: U and V live in separate planes, pixelStride = 1.
    // Semi-planar format (NV12/NV21): U and V are interleaved, pixelStride = 2.
    final bool isPlanar = pixelStrides[1] == 1;

    // Neutral gray value used for letterbox padding.
    const double gray = 114.0 / 255.0;
    int outIdx = 0;

    for (int oy = 0; oy < inputSize; oy++) {
      for (int ox = 0; ox < inputSize; ox++) {
        final int lx = ox - padL;
        final int ly = oy - padT;

        // Fill padded regions with neutral gray.
        if (lx < 0 || lx >= scaledW || ly < 0 || ly >= scaledH) {
          tensor[outIdx] = gray;
          tensor[outIdx + 1] = gray;
          tensor[outIdx + 2] = gray;
          outIdx += 3;
          continue;
        }

        // Map scaled coordinates back to the original rotated image.
        final int rx = ((lx / scale) + 0.5).toInt().clamp(0, rotW - 1);
        final int ry = ((ly / scale) + 0.5).toInt().clamp(0, rotH - 1);

        // Apply inverse rotation from rotated space back to original source coordinates.
        int srcX, srcY;
        switch (rotationDegrees) {
          case 90: // Rotate left.
            srcX = ry;
            srcY = srcHeight - 1 - rx;
            break;
          case 270: // Rotate right.
            srcX = srcWidth - 1 - ry;
            srcY = rx;
            break;
          case 180:
            srcX = srcWidth - 1 - rx;
            srcY = srcHeight - 1 - ry;
            break;
          default: // 0 degrees, no transform.
            srcX = rx;
            srcY = ry;
        }

        final int yIdx = srcY * yStride + srcX;
        final int uvRow = srcY ~/ 2;
        final int uvCol = srcX ~/ 2;
        final int uvIdx = isPlanar
            ? uvRow * uvStride + uvCol
            : uvRow * uvStride + uvCol * uvPixStride;

        // Guard against out-of-bounds reads. Fall back to gray instead of crashing.
        if (yIdx >= yPlane.length ||
            uvIdx >= uPlane.length ||
            uvIdx >= vPlane.length) {
          tensor[outIdx] = gray;
          tensor[outIdx + 1] = gray;
          tensor[outIdx + 2] = gray;
          outIdx += 3;
          continue;
        }

        final int yy = yPlane[yIdx];
        final int uu = uPlane[uvIdx] - 128;
        final int vv = vPlane[uvIdx] - 128;

        // Convert BT.601 YCbCr to RGB, clamp to [0, 255], then normalize.
        tensor[outIdx] = (yy + 1.402 * vv).clamp(0, 255) / 255.0;
        tensor[outIdx + 1] =
            (yy - 0.344136 * uu - 0.714136 * vv).clamp(0, 255) / 255.0;
        tensor[outIdx + 2] = (yy + 1.772 * uu).clamp(0, 255) / 255.0;
        outIdx += 3;
      }
    }

    return LetterboxResult(
      inputTensor: tensor,
      scale: scale,
      padLeft: padL / inputSize,
      padTop: padT / inputSize,
      origWidth: rotW,
      origHeight: rotH,
    );
  }

  /// Letterbox variant for an already-decoded [img.Image].
  /// Used when the input does not come from the camera stream, such as a file.
  static LetterboxResult letterboxAndNormalize(
    img.Image image,
    int inputSize,
  ) {
    final scale =
        inputSize / (image.width > image.height ? image.width : image.height);
    final scaledW = (image.width * scale).round().clamp(1, inputSize);
    final scaledH = (image.height * scale).round().clamp(1, inputSize);
    final padL = (inputSize - scaledW) ~/ 2;
    final padT = (inputSize - scaledH) ~/ 2;
    final resized = img.copyResize(image, width: scaledW, height: scaledH);
    final tensor = Float32List(inputSize * inputSize * 3);
    const gray = 114.0 / 255.0;

    int outIdx = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final rx = x - padL;
        final ry = y - padT;
        if (rx < 0 || ry < 0 || rx >= scaledW || ry >= scaledH) {
          tensor[outIdx] = gray;
          tensor[outIdx + 1] = gray;
          tensor[outIdx + 2] = gray;
        } else {
          final pixel = resized.getPixel(rx, ry);
          tensor[outIdx] = pixel.r / 255.0;
          tensor[outIdx + 1] = pixel.g / 255.0;
          tensor[outIdx + 2] = pixel.b / 255.0;
        }
        outIdx += 3;
      }
    }

    return LetterboxResult(
      inputTensor: tensor,
      scale: scale,
      padLeft: padL / inputSize,
      padTop: padT / inputSize,
      origWidth: image.width,
      origHeight: image.height,
    );
  }

  /// Converts YUV420 input into an RGB [img.Image].
  /// Detects planar vs semi-planar layout automatically from [pixelStrides].
  static img.Image convertYuv420(
    List<Uint8List> planes,
    List<int> rowStrides,
    List<int> pixelStrides,
    int width,
    int height,
  ) {
    final isPlanar = pixelStrides[1] == 1;
    return isPlanar
        ? _convertPlanar(planes, rowStrides, width, height)
        : _convertSemiPlanar(planes, rowStrides, pixelStrides, width, height);
  }

  /// Planar format: Y, U, and V are stored in separate planes.
  static img.Image _convertPlanar(
    List<Uint8List> planes,
    List<int> strides,
    int w,
    int h,
  ) {
    final rgb = Uint8List(w * h * 3);
    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];
    final yStr = strides[0];
    final uvStr = strides[1];
    int out = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final yIndex = y * yStr + x;
        final uvIndex = (y ~/ 2) * uvStr + (x ~/ 2);

        if (yIndex >= yPlane.length ||
            uvIndex >= uPlane.length ||
            uvIndex >= vPlane.length) {
          rgb[out++] = 114;
          rgb[out++] = 114;
          rgb[out++] = 114;
          continue;
        }

        final yy = yPlane[yIndex];
        final uu = uPlane[uvIndex] - 128;
        final vv = vPlane[uvIndex] - 128;
        rgb[out++] = (yy + 1.402 * vv).round().clamp(0, 255);
        rgb[out++] = (yy - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255);
        rgb[out++] = (yy + 1.772 * uu).round().clamp(0, 255);
      }
    }
    return img.Image.fromBytes(
        width: w,
        height: h,
        bytes: rgb.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb);
  }

  /// Semi-planar format (NV12/NV21): U and V are interleaved.
  static img.Image _convertSemiPlanar(
    List<Uint8List> planes,
    List<int> rowStrides,
    List<int> pixelStrides,
    int w,
    int h,
  ) {
    final rgb = Uint8List(w * h * 3);
    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];
    final yStr = rowStrides[0];
    final uvStr = rowStrides[1];
    final uvPxStr = pixelStrides[1];
    int out = 0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final yIndex = y * yStr + x;
        final uvIndex = (y ~/ 2) * uvStr + (x ~/ 2) * uvPxStr;

        if (yIndex >= yPlane.length ||
            uvIndex >= uPlane.length ||
            uvIndex >= vPlane.length) {
          rgb[out++] = 114;
          rgb[out++] = 114;
          rgb[out++] = 114;
          continue;
        }

        final yy = yPlane[yIndex];
        final uu = uPlane[uvIndex] - 128;
        final vv = vPlane[uvIndex] - 128;
        rgb[out++] = (yy + 1.402 * vv).round().clamp(0, 255);
        rgb[out++] = (yy - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255);
        rgb[out++] = (yy + 1.772 * uu).round().clamp(0, 255);
      }
    }

    return img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgb.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
  }

  /// Converts bounding-box coordinates from model space
  /// (normalized by `inputSize`, including padding) back into the original
  /// image space `[0.0, 1.0]`.
  ///
  /// [cx], [cy], [bw], and [bh] are model outputs relative to `inputSize`.
  /// This function removes the effects of letterboxing and scaling.
  static ({double left, double top, double width, double height})
      unLetterboxBox({
    required double cx,
    required double cy,
    required double bw,
    required double bh,
    required double padLeft,
    required double padTop,
    required double scale,
    required int origWidth,
    required int origHeight,
    required int inputSize,
  }) {
    // Convert normalized values to pixel coordinates in inputSize space.
    final cxPx = cx * inputSize;
    final cyPx = cy * inputSize;
    final wPx = bw * inputSize;
    final hPx = bh * inputSize;
    final padLPx = padLeft * inputSize;
    final padTPx = padTop * inputSize;

    // Remove padding, then invert the scale.
    final x1 = (cxPx - wPx / 2 - padLPx) / scale;
    final y1 = (cyPx - hPx / 2 - padTPx) / scale;
    final w = wPx / scale;
    final h = hPx / scale;

    return (
      left: (x1 / origWidth).clamp(0.0, 1.0),
      top: (y1 / origHeight).clamp(0.0, 1.0),
      width: (w / origWidth).clamp(0.0, 1.0),
      height: (h / origHeight).clamp(0.0, 1.0),
    );
  }
}
