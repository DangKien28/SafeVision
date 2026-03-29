import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection_local_datasource.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_paths.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/image_converter.dart';

class DetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  Interpreter? _interpreter;
  List<String> _labels = [];
  List<int> _outputShape = [];
  bool _modelLoaded = false;
  bool _isRunning = false;

  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _mainReceivePort;

  // ── Load model ─────────────────────────────────────────────────────────────

  @override
  Future<void> loadModel() async {
    try {
      final raw = await rootBundle.loadString(AssetPaths.labels);
      _labels = raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        AssetPaths.modelFile,
        options: options,
      );

      _outputShape = _interpreter!.getOutputTensor(0).shape;
      final inShape = _interpreter!.getInputTensor(0).shape;
      final outType = _interpreter!.getOutputTensor(0).type;

      debugPrint('[DS]  Model loaded');
      debugPrint('[DS]   labels   = ${_labels.length}');
      debugPrint('[DS]   input    = $inShape');
      debugPrint('[DS]   output   = $_outputShape  type=$outType');
      debugPrint('[DS]   inputSize= ${AppConstants.inputSize}');

      _modelLoaded = true;
      await _spawnIsolate();
      debugPrint('[DS] Isolate ready');
    } catch (e, st) {
      debugPrint('[DS]  loadModel FAILED: $e\n$st');
      throw ModelNotFoundException('Không thể tải model: $e');
    }
  }

  // ── Persistent isolate ─────────────────────────────────────────────────────

  Future<void> _spawnIsolate() async {
    _mainReceivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, _mainReceivePort!.sendPort);
    _isolateSendPort = await _mainReceivePort!.first as SendPort;
  }

  // ── Inference ──────────────────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> runInference(CameraImage image) async {
    if (!_modelLoaded || _interpreter == null || _isolateSendPort == null) {
      return [];
    }
    if (_isRunning) return [];
    _isRunning = true;

    try {
      // Copy bytes NGAY để giải phóng camera buffer
      final planeBytes =
          image.planes.map((p) => Uint8List.fromList(p.bytes)).toList();
      final rowStrides = image.planes.map((p) => p.bytesPerRow).toList();
      final pixelStrides =
          image.planes.map((p) => p.bytesPerPixel ?? 1).toList();

      final replyPort = ReceivePort();
      _isolateSendPort!.send(_InferenceJob(
        replyPort: replyPort.sendPort,
        planeBytes: planeBytes,
        planeRowStrides: rowStrides,
        planePixelStrides: pixelStrides,
        imageWidth: image.width,
        imageHeight: image.height,
        // Android: camera stream rotated 90° CW → cần xoay ngược lại
        rotationDegrees: 90,
        interpreterAddress: _interpreter!.address,
        labels: List.unmodifiable(_labels),
        inputSize: AppConstants.inputSize,
        outputShape: _outputShape,
        confidenceThreshold: AppConstants.confidenceThreshold,
        iouThreshold: AppConstants.iouThreshold,
        maxDetections: AppConstants.maxDetections,
      ));

      final dynamic result = await replyPort.first;
      replyPort.close();

      if (result is String) {
        debugPrint('[DS]  isolate error: $result');
        return [];
      }

      final list = List<Map<String, dynamic>>.from(result as List);
      debugPrint('[DS] detections=${list.length}');
      return list;
    } catch (e) {
      debugPrint('[DS] runInference exception: $e');
      return [];
    } finally {
      _isRunning = false;
    }
  }

  @override
  Future<void> closeModel() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _isolateSendPort = null;
    _interpreter?.close();
    _interpreter = null;
    _modelLoaded = false;
    _isRunning = false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ISOLATE
// ═══════════════════════════════════════════════════════════════════════════

void _isolateEntry(SendPort mainSendPort) {
  final jobPort = ReceivePort();
  mainSendPort.send(jobPort.sendPort);
  jobPort.listen((msg) {
    if (msg is _InferenceJob) _processJob(msg);
  });
}

void _processJob(_InferenceJob job) {
  try {
    final interpreter = Interpreter.fromAddress(job.interpreterAddress);

    // ── 1. Convert YUV420 → RGB image ──────────────────────────────────────
    img.Image rawImage = _convertYuv420(
      job.planeBytes,
      job.planeRowStrides,
      job.planePixelStrides,
      job.imageWidth,
      job.imageHeight,
    );

    // ── 2. FIX: Xoay ảnh 90° CCW để compensate camera rotation ────────────
    // Android back camera: ảnh stream bị xoay 90° CW so với thực tế
    // Phải xoay ngược lại 90° CCW (= 270° CW) trước khi inference
    if (job.rotationDegrees == 90) {
      rawImage = img.copyRotate(rawImage, angle: -90);
    } else if (job.rotationDegrees == 270) {
      rawImage = img.copyRotate(rawImage, angle: 90);
    } else if (job.rotationDegrees == 180) {
      rawImage = img.copyRotate(rawImage, angle: 180);
    }

    // ── 3. Resize về inputSize (640×640) ───────────────────────────────────
    final resized = img.copyResize(
      rawImage,
      width: job.inputSize,
      height: job.inputSize,
      interpolation: img.Interpolation.linear,
    );

    // ── 4. Normalize về [0,1] và tạo input tensor [1,640,640,3] ───────────
    final inputSize = job.inputSize;
    final inputFlat = Float32List(inputSize * inputSize * 3);
    int idx = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        inputFlat[idx++] = pixel.r / 255.0;
        inputFlat[idx++] = pixel.g / 255.0;
        inputFlat[idx++] = pixel.b / 255.0;
      }
    }
    final inputTensor = inputFlat.reshape([1, inputSize, inputSize, 3]);

    // ── 5. Tạo output buffer khớp shape [1, channels, 8400] ────────────────
    final d0 = job.outputShape[0]; // 1
    final d1 = job.outputShape[1]; // 5 hoặc 85
    final d2 = job.outputShape[2]; // 8400

    final outputBuffer = List.generate(
      d0,
      (_) => List.generate(
        d1,
        (_) => List<double>.filled(d2, 0.0),
      ),
    );

    // ── 6. Chạy inference ───────────────────────────────────────────────────
    interpreter.run(inputTensor, outputBuffer);

    // ── 7. Parse kết quả ────────────────────────────────────────────────────
    final results = _parseYoloOutput(
      data: outputBuffer[0], // [channels][8400]
      outputShape: job.outputShape,
      labels: job.labels,
      inputSize: job.inputSize,
      confidenceThreshold: job.confidenceThreshold,
      iouThreshold: job.iouThreshold,
      maxDetections: job.maxDetections,
    );

    job.replyPort.send(results);
  } catch (e, st) {
    job.replyPort.send('ERROR: $e\n$st');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PARSE YOLO OUTPUT — hỗ trợ [1,5,8400] và [1,85,8400]
// ═══════════════════════════════════════════════════════════════════════════

List<Map<String, dynamic>> _parseYoloOutput({
  required List<List<double>> data,
  required List<int> outputShape,
  required List<String> labels,
  required int inputSize,
  required double confidenceThreshold,
  required double iouThreshold,
  required int maxDetections,
}) {
  final numBoxes = outputShape[2]; // 8400

  // ── Tự detect model đã apply sigmoid chưa ─────────────────────────────
  // Lấy 200 box sample, tính max raw confidence
  double maxRaw = 0;
  double minRaw = double.infinity;
  for (int i = 0; i < min(numBoxes, 200); i++) {
    final v = data[4][i];
    if (v > maxRaw) maxRaw = v;
    if (v < minRaw) minRaw = v;
  }

  // Nếu tất cả giá trị trong [0, 1] → model đã sigmoid sẵn → KHÔNG apply sigmoid
  // Nếu có giá trị âm hoặc > 1    → model output logit  → CẦN apply sigmoid
  final needSigmoid = minRaw < -0.1 || maxRaw > 1.05;

  debugPrint('[Parse] outputShape=$outputShape');
  debugPrint('[Parse] confRange=[$minRaw, $maxRaw]  needSigmoid=$needSigmoid');
  debugPrint('[Parse] threshold=$confidenceThreshold');
  debugPrint('[Parse] sample box0: '
      'cx=${data[0][0].toStringAsFixed(4)} '
      'cy=${data[1][0].toStringAsFixed(4)} '
      'w=${data[2][0].toStringAsFixed(4)} '
      'h=${data[3][0].toStringAsFixed(4)} '
      'conf=${data[4][0].toStringAsFixed(6)}');

  // ── Detect coordinate format ───────────────────────────────────────────
  // Sample w values để biết normalized hay pixel
  final sampleW = data[2].take(50).map((v) => v.abs()).reduce(max);
  final isNormalized = sampleW < 2.0;

  debugPrint(
      '[Parse] coordFormat=${isNormalized ? "normalized[0,1]" : "pixel[0,$inputSize]"}');

  final rawBoxes = <_RawBox>[];

  for (int i = 0; i < numBoxes; i++) {
    final cx = data[0][i];
    final cy = data[1][i];
    final w = data[2][i];
    final h = data[3][i];

    if (w <= 0 || h <= 0) continue;

    // ── FIX CHÍNH: chỉ apply sigmoid khi thực sự cần ──────────────────
    final rawConf = data[4][i];
    final score = needSigmoid ? _sigmoid(rawConf) : rawConf;

    if (score < confidenceThreshold) continue;

    // ── Normalize tọa độ ───────────────────────────────────────────────
    final double normLeft, normTop, normW, normH;
    if (isNormalized) {
      normLeft = cx - w / 2;
      normTop = cy - h / 2;
      normW = w;
      normH = h;
    } else {
      normLeft = (cx - w / 2) / inputSize;
      normTop = (cy - h / 2) / inputSize;
      normW = w / inputSize;
      normH = h / inputSize;
    }

    if (normLeft + normW <= 0 || normTop + normH <= 0) continue;
    if (normLeft >= 1.0 || normTop >= 1.0) continue;

    rawBoxes.add(_RawBox(
      left: normLeft,
      top: normTop,
      width: normW,
      height: normH,
      score: score,
      classId: 0,
    ));
  }

  debugPrint('[Parse] raw boxes before NMS: ${rawBoxes.length}');

  final kept = _nms(rawBoxes, iouThreshold);

  debugPrint('[Parse] boxes after NMS: ${kept.length}');
  for (final b in kept.take(5)) {
    debugPrint(
        '[Parse]   → ${labels.elementAtOrNull(b.classId) ?? "cls_${b.classId}"} '
        'score=${b.score.toStringAsFixed(4)} '
        'box=[${b.left.toStringAsFixed(3)}, ${b.top.toStringAsFixed(3)}, '
        '${b.width.toStringAsFixed(3)}, ${b.height.toStringAsFixed(3)}]');
  }

  return kept.take(maxDetections).map((b) {
    final label =
        b.classId < labels.length ? labels[b.classId] : 'class_${b.classId}';
    return <String, dynamic>{
      'label': label,
      'confidence': b.score,
      'left': b.left.clamp(0.0, 1.0),
      'top': b.top.clamp(0.0, 1.0),
      'width': b.width.clamp(0.0, 1.0),
      'height': b.height.clamp(0.0, 1.0),
    };
  }).toList();
}

// ── Sigmoid ────────────────────────────────────────────────────────────────
double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

// ── NMS ───────────────────────────────────────────────────────────────────
List<_RawBox> _nms(List<_RawBox> boxes, double iouThreshold) {
  boxes.sort((a, b) => b.score.compareTo(a.score));
  final result = <_RawBox>[];
  for (final box in boxes) {
    bool suppressed = false;
    for (final kept in result) {
      if (box.classId == kept.classId && _iou(box, kept) > iouThreshold) {
        suppressed = true;
        break;
      }
    }
    if (!suppressed) result.add(box);
  }
  return result;
}

double _iou(_RawBox a, _RawBox b) {
  final iL = max(a.left, b.left);
  final iT = max(a.top, b.top);
  final iR = min(a.left + a.width, b.left + b.width);
  final iB = min(a.top + a.height, b.top + b.height);
  if (iR <= iL || iB <= iT) return 0.0;
  final inter = (iR - iL) * (iB - iT);
  return inter / (a.width * a.height + b.width * b.height - inter);
}

// ── YUV420 → RGB (inline, không dùng ImageConverter để tránh import issues) ─
img.Image _convertYuv420(
  List<Uint8List> planes,
  List<int> rowStrides,
  List<int> pixelStrides,
  int width,
  int height,
) {
  final result = img.Image(width: width, height: height);
  final yPlane = planes[0];
  final uPlane = planes[1];
  final vPlane = planes[2];
  final uvRowStr = rowStrides[1];
  final uvPixStr = pixelStrides[1];

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIdx = y * width + x;
      final uvIdx = (y ~/ 2) * uvRowStr + (x ~/ 2) * uvPixStr;

      if (yIdx >= yPlane.length) continue;
      if (uvIdx >= uPlane.length || uvIdx >= vPlane.length) continue;

      final yVal = yPlane[yIdx];
      final uVal = uPlane[uvIdx] - 128;
      final vVal = vPlane[uvIdx] - 128;

      final r = (yVal + 1.402 * vVal).round().clamp(0, 255);
      final g =
          (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
      final b = (yVal + 1.772 * uVal).round().clamp(0, 255);

      result.setPixelRgb(x, y, r, g, b);
    }
  }
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

class _RawBox {
  final double left, top, width, height, score;
  final int classId;
  const _RawBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.score,
    required this.classId,
  });
}

class _InferenceJob {
  final SendPort replyPort;
  final List<Uint8List> planeBytes;
  final List<int> planeRowStrides;
  final List<int> planePixelStrides;
  final int imageWidth;
  final int imageHeight;
  final int rotationDegrees; // ← FIX: truyền rotation
  final int interpreterAddress;
  final List<String> labels;
  final int inputSize;
  final List<int> outputShape;
  final double confidenceThreshold;
  final double iouThreshold;
  final int maxDetections;

  const _InferenceJob({
    required this.replyPort,
    required this.planeBytes,
    required this.planeRowStrides,
    required this.planePixelStrides,
    required this.imageWidth,
    required this.imageHeight,
    required this.rotationDegrees,
    required this.interpreterAddress,
    required this.labels,
    required this.inputSize,
    required this.outputShape,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.maxDetections,
  });
}
