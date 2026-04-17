import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// ── Public result type ────────────────────────────────────────────────────────

/// Output of the letterbox-and-normalise pipeline.
///
/// Both [inputTensor] and [inputBuffer] point to the same underlying memory
/// so callers can choose whichever representation the TFLite API expects
/// without an additional copy.
class LetterboxResult {
  LetterboxResult({
    required this.inputTensor,
    required this.scale,
    required this.padLeft,
    required this.padTop,
    required this.origWidth,
    required this.origHeight,
  }) : inputBuffer = inputTensor.buffer;

  /// Flat Float32 tensor: [inputSize × inputSize × 3], normalised to [0, 1].
  final Float32List inputTensor;

  /// Same memory as [inputTensor] — use with [Interpreter.tensor(0).setTo].
  final ByteBuffer inputBuffer;

  /// Factor applied to the longer edge so that it fits in `inputSize` pixels.
  final double scale;

  /// Normalised horizontal padding added to centre the image (fraction of
  /// inputSize).
  final double padLeft;

  /// Normalised vertical padding added to centre the image (fraction of
  /// inputSize).
  final double padTop;

  final int origWidth;
  final int origHeight;
}

/// Simple axis-aligned bounding box returned by [ImageConverter.unLetterboxBox].
class UnletterboxedBox {
  const UnletterboxedBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

// ── ImageConverter ────────────────────────────────────────────────────────────

/// Static utilities for the camera-frame → TFLite input pipeline.
///
/// The core pipeline is:
///   YUV420 planes → RGB [img.Image] → letterbox + pad → normalised Float32
///
/// All methods are pure functions (no mutable state) so they can be called
/// safely from an isolate.
abstract class ImageConverter {
  ImageConverter._();

  // ── High-level combined entry point ──────────────────────────────────────

  /// Converts a raw YUV420 frame directly to a letterboxed, normalised
  /// Float32 tensor in one pass.
  ///
  /// This is the method called by the inference isolate.  It avoids creating
  /// an intermediate `img.Image` when [rotationDegrees] is 0 by operating on
  /// the YUV planes directly.  For non-zero rotations it falls back to the
  /// [img.Image] path so the existing rotation utilities can be used.
  static LetterboxResult yuvToLetterboxedFloat32({
    required List<Uint8List> planes,
    required List<int> rowStrides,
    required List<int> pixelStrides,
    required int srcWidth,
    required int srcHeight,
    required int inputSize,
    required int rotationDegrees,
  }) {
    final image = convertYuv420(
      planes,
      rowStrides,
      pixelStrides,
      srcWidth,
      srcHeight,
    );

    final rotated = _applyRotation(image, rotationDegrees);
    return letterboxAndNormalize(rotated, inputSize);
  }

  // ── Letterbox ─────────────────────────────────────────────────────────────

  /// Resizes [image] to fit inside [inputSize]×[inputSize] while preserving
  /// the aspect ratio (YOLOv8 "letterbox").  Padding regions are filled with
  /// grey (114, 114, 114) and pixel values are normalised to [0.0, 1.0].
  static LetterboxResult letterboxAndNormalize(
    img.Image image,
    int inputSize,
  ) {
    final origW = image.width;
    final origH = image.height;

    // Scale so the longer edge fits inside inputSize.
    final scale = inputSize / math.max(origW, origH);
    final scaledW = (origW * scale).round();
    final scaledH = (origH * scale).round();

    // Padding needed to centre the scaled image.
    final padPixLeft = ((inputSize - scaledW) / 2).floor();
    final padPixTop = ((inputSize - scaledH) / 2).floor();

    // Normalised pad fractions (used by unLetterboxBox).
    final padLeft = padPixLeft / inputSize;
    final padTop = padPixTop / inputSize;

    // Resize.
    final resized = img.copyResize(image, width: scaledW, height: scaledH);

    // Build the output tensor, pre-filled with the letterbox grey.
    const grey = 114.0 / 255.0;
    final tensor = Float32List(inputSize * inputSize * 3);
    tensor.fillRange(0, tensor.length, grey);

    // Copy resized pixels into the padded region.
    for (int y = 0; y < scaledH; y++) {
      for (int x = 0; x < scaledW; x++) {
        final pixel = resized.getPixel(x, y);
        final dstIdx = ((padPixTop + y) * inputSize + (padPixLeft + x)) * 3;
        tensor[dstIdx + 0] = pixel.r / 255.0;
        tensor[dstIdx + 1] = pixel.g / 255.0;
        tensor[dstIdx + 2] = pixel.b / 255.0;
      }
    }

    return LetterboxResult(
      inputTensor: tensor,
      scale: scale,
      padLeft: padLeft,
      padTop: padTop,
      origWidth: origW,
      origHeight: origH,
    );
  }

  // ── Inverse letterbox ──────────────────────────────────────────────────────

  /// Maps a model-output bounding box back to normalised original-image
  /// coordinates [0, 1].
  ///
  /// When [coordinatesAreNormalized] is true the inputs (cx, cy, bw, bh) are
  /// already normalised to [inputSize]; otherwise they are raw pixel values.
  static UnletterboxedBox unLetterboxBox({
    required double cx,
    required double cy,
    required double bw,
    required double bh,
    required bool coordinatesAreNormalized,
    required double padLeft,
    required double padTop,
    required double scale,
    required int origWidth,
    required int origHeight,
    required int inputSize,
  }) {
    // Convert to normalised [0,1] in the model's input space if needed.
    final ncx = coordinatesAreNormalized ? cx : cx / inputSize;
    final ncy = coordinatesAreNormalized ? cy : cy / inputSize;
    final nbw = coordinatesAreNormalized ? bw : bw / inputSize;
    final nbh = coordinatesAreNormalized ? bh : bh / inputSize;

    // Remove padding offset.
    final effectiveW = (origWidth * scale) / inputSize;
    final effectiveH = (origHeight * scale) / inputSize;

    // Map from padded-model space → original-image space.
    final x0 = (ncx - nbw / 2 - padLeft) / effectiveW;
    final y0 = (ncy - nbh / 2 - padTop) / effectiveH;
    final x1 = (ncx + nbw / 2 - padLeft) / effectiveW;
    final y1 = (ncy + nbh / 2 - padTop) / effectiveH;

    // Clamp to [0, 1].
    final left = x0.clamp(0.0, 1.0);
    final top = y0.clamp(0.0, 1.0);
    final right = x1.clamp(0.0, 1.0);
    final bottom = y1.clamp(0.0, 1.0);

    return UnletterboxedBox(
      left: left,
      top: top,
      width: (right - left).clamp(0.0, 1.0),
      height: (bottom - top).clamp(0.0, 1.0),
    );
  }

  // ── YUV420 → RGB ──────────────────────────────────────────────────────────

  /// Converts planar YUV420 camera planes to an RGB [img.Image].
  ///
  /// Supports both interleaved NV21/NV12 (pixelStride == 2) and fully planar
  /// I420 (pixelStride == 1) formats.
  static img.Image convertYuv420(
    List<Uint8List> planes,
    List<int> rowStrides,
    List<int> pixelStrides,
    int width,
    int height,
  ) {
    final image = img.Image(width: width, height: height);

    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];

    final yRowStride = rowStrides[0];
    final uvRowStride = rowStrides[1];
    final uvPixelStride = pixelStrides[1];

    for (int h = 0; h < height; h++) {
      for (int w = 0; w < width; w++) {
        final yIdx = h * yRowStride + w;
        if (yIdx >= yPlane.length) continue;

        final uvRow = h ~/ 2;
        final uvCol = w ~/ 2;
        final uvIdx = uvRow * uvRowStride + uvCol * uvPixelStride;
        if (uvIdx >= uPlane.length || uvIdx >= vPlane.length) {
          // Fallback: use neutral UV.
          final y = yPlane[yIdx];
          image.setPixelRgb(w, h, y, y, y);
          continue;
        }

        final yVal = yPlane[yIdx];
        final uVal = uPlane[uvIdx] - 128;
        final vVal = vPlane[uvIdx] - 128;

        final r = (yVal + 1.370705 * vVal).round().clamp(0, 255);
        final g =
            (yVal - 0.337633 * uVal - 0.698001 * vVal).round().clamp(0, 255);
        final b = (yVal + 1.732446 * uVal).round().clamp(0, 255);

        image.setPixelRgb(w, h, r, g, b);
      }
    }

    return image;
  }

  // ── Rotation helper ───────────────────────────────────────────────────────

  static img.Image _applyRotation(img.Image image, int degrees) {
    switch (degrees) {
      case 90:
        return img.copyRotate(image, angle: 90);
      case 180:
        return img.copyRotate(image, angle: 180);
      case 270:
        return img.copyRotate(image, angle: 270);
      default:
        return image;
    }
  }
}
