import 'package:flutter/foundation.dart';
import '../../features/detection/domain/entities/detection_object.dart';
import '../constants/app_constants.dart';

class AiHelper {
  AiHelper._();

  /// Parse YOLOv8 TFLite output.
  ///
  /// Hỗ trợ cả 2 format output:
  ///   - Transposed:     [1, 84, 8400]  (Ultralytics default TFLite export)
  ///   - Non-transposed: [1, 8400, 84]  (một số export cũ)
  ///
  /// Tọa độ YOLOv8 là ABSOLUTE PIXELS (0 → inputSize).
  /// Phải chia cho inputSize để normalize về [0, 1].
  static List<DetectionObject> parseYoloV8Output({
    required List<List<List<double>>> output, // [1][?][?]
    required List<String> labels,
    required int inputSize, // ← THÊM PARAM NÀY
    double confidenceThreshold = AppConstants.confidenceThreshold,
    double iouThreshold        = AppConstants.iouThreshold,
    int    maxDetections       = AppConstants.maxDetections,
  }) {
    final batch = output[0]; // shape [84][8400] hoặc [8400][84]

    final dim0 = batch.length;
    final dim1 = batch[0].length;

    // Detect output format
    // Transposed [84, 8400]:   dim0=84,   dim1=8400
    // Non-transposed [8400, 84]: dim0=8400, dim1=84
    final bool isTransposed = dim0 < dim1;

    final int numBoxes   = isTransposed ? dim1 : dim0;
    final int numFields  = isTransposed ? dim0 : dim1; // should be 4 + numClasses
    final int numClasses = numFields - 4;

    debugPrint('[AiHelper] format=${isTransposed ? "transposed [84,8400]" : "non-transposed [8400,84]"} '
        'boxes=$numBoxes classes=$numClasses inputSize=$inputSize');

    if (numClasses <= 0) {
      debugPrint('[AiHelper] ERROR: numClasses=$numClasses — output shape wrong!');
      return [];
    }

    final List<_RawBox> rawBoxes = [];

    for (int i = 0; i < numBoxes; i++) {
      double cx, cy, w, h;
      double maxScore = 0;
      int    maxClass = 0;

      if (isTransposed) {
        // batch[channel][boxIndex]
        cx = batch[0][i];
        cy = batch[1][i];
        w  = batch[2][i];
        h  = batch[3][i];

        for (int c = 0; c < numClasses; c++) {
          final score = batch[4 + c][i];
          if (score > maxScore) { maxScore = score; maxClass = c; }
        }
      } else {
        // batch[boxIndex][channel]
        cx = batch[i][0];
        cy = batch[i][1];
        w  = batch[i][2];
        h  = batch[i][3];

        for (int c = 0; c < numClasses; c++) {
          final score = batch[i][4 + c];
          if (score > maxScore) { maxScore = score; maxClass = c; }
        }
      }

      if (maxScore < confidenceThreshold) continue;

      // ─────────────────────────────────────────────────────────
      // FIX CHÍNH: chia cho inputSize để normalize về [0, 1]
      // YOLOv8 TFLite output là pixel tuyệt đối (0→640)
      // KHÔNG normalize = tất cả box bị clamp thành (1.0, 1.0)
      // ─────────────────────────────────────────────────────────
      final normCx = cx / inputSize;
      final normCy = cy / inputSize;
      final normW  = w  / inputSize;
      final normH  = h  / inputSize;

      final left = normCx - normW / 2;
      final top  = normCy - normH / 2;

      rawBoxes.add(_RawBox(
        left:       left,
        top:        top,
        width:      normW,
        height:     normH,
        classIndex: maxClass,
        score:      maxScore,
      ));
    }

    debugPrint('[AiHelper] raw boxes before NMS: ${rawBoxes.length}');

    final nmsResult = _nms(rawBoxes, iouThreshold);

    debugPrint('[AiHelper] boxes after NMS: ${nmsResult.length}');

    return nmsResult.take(maxDetections).map((b) {
      final label = b.classIndex < labels.length
          ? labels[b.classIndex]
          : 'class_${b.classIndex}';
      return DetectionObject(
        label:      label,
        confidence: b.score,
        boundingBox: BoundingBox(
          left:   b.left.clamp(0.0, 1.0),
          top:    b.top.clamp(0.0, 1.0),
          width:  b.width.clamp(0.0, 1.0),
          height: b.height.clamp(0.0, 1.0),
        ),
      );
    }).toList();
  }

  static List<_RawBox> _nms(List<_RawBox> boxes, double iouThreshold) {
    boxes.sort((a, b) => b.score.compareTo(a.score));
    final List<_RawBox> result = [];
    for (final box in boxes) {
      bool suppressed = false;
      for (final kept in result) {
        if (box.classIndex == kept.classIndex && _iou(box, kept) > iouThreshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) result.add(box);
    }
    return result;
  }

  static double _iou(_RawBox a, _RawBox b) {
    final iL = a.left > b.left ? a.left : b.left;
    final iT = a.top  > b.top  ? a.top  : b.top;
    final iR = (a.left + a.width)  < (b.left + b.width)
        ? (a.left + a.width)  : (b.left + b.width);
    final iB = (a.top  + a.height) < (b.top  + b.height)
        ? (a.top  + a.height) : (b.top  + b.height);
    if (iR <= iL || iB <= iT) return 0;
    final inter = (iR - iL) * (iB - iT);
    return inter / (a.width * a.height + b.width * b.height - inter);
  }
}

class _RawBox {
  final double left, top, width, height, score;
  final int classIndex;
  const _RawBox({
    required this.left, required this.top,
    required this.width, required this.height,
    required this.classIndex, required this.score,
  });
}