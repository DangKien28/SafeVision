import 'dart:isolate';
import 'dart:math';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection_local_datasource.dart';
import '../../../../core/config/detection_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_paths.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/image_converter.dart';

/// Runs YOLOv8 inference inside a dedicated Dart isolate so the UI thread
/// never blocks. The model is loaded once when the isolate starts, then
/// [_InferenceJob] messages are received through a [SendPort].
///
/// Delegate selection strategy (Android):
///   1. NNAPI — most stable on target devices (MTK)
///   2. CPU   — reliable fallback
///   GPU delegate is intentionally excluded: on devices where libOpenCL.so
///   is absent or transpose ops are unsupported, the GPU delegate fails
///   *after* setting delegateEnabled=true, causing silent CPU fallback with
///   no thread optimization. More critically, on some MTK devices the GPU
///   delegate partially modifies the execution graph before failing; TFLite's
///   plan restoration then leaves CONCATENATION node tensor dimensions in a
///   corrupted state, causing the (20 != 40) crash reproduced in production.
///
/// If the isolate times out 3 times in a row, it is killed and respawned to
/// recover from a potentially stuck state.
class DetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  DetectionLocalDatasourceImpl(this._config);

  final DetectionConfig _config;

  List<String> _labels = [];
  List<int> _outputShape = [];
  bool _modelLoaded = false;

  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _mainReceivePort;
  int _consecutiveTimeouts = 0;

  @override
  Future<void> loadModel() async {
    if (_modelLoaded) {
      debugPrint('[DS] loadModel: already loaded, skipping');
      return;
    }
    try {
      final raw = await rootBundle.loadString(AssetPaths.labels);
      _labels = raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final modelData = await rootBundle.load(AssetPaths.modelFile);
      final modelBytes = modelData.buffer.asUint8List();

      await _spawnIsolate(modelBytes);

      if (kDebugMode) {
        debugPrint(
            '[DS] Model OK in isolate — threads=${AppConstants.inferenceThreads}');
        debugPrint('[DS]   output = $_outputShape  labels=${_labels.length}');
      }

      _modelLoaded = true;
    } catch (e, st) {
      debugPrint('[DS] loadModel FAILED: $e\n$st');
      throw ModelNotFoundException('Cannot load model: $e');
    }
  }

  /// Spawns the isolate and waits for an ack confirming that the model loaded
  /// successfully. Model bytes are passed with [TransferableTypedData] to avoid
  /// extra copies.
  Future<void> _spawnIsolate(Uint8List modelBytes) async {
    _mainReceivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, _mainReceivePort!.sendPort);
    _isolateSendPort = await _mainReceivePort!.first as SendPort;

    final ackPort = ReceivePort();
    _isolateSendPort!.send(_IsolateInitMsg(
      labels: List.unmodifiable(_labels),
      inputSize: AppConstants.inputSize,
      modelBytes: TransferableTypedData.fromList([modelBytes]),
      ackPort: ackPort.sendPort,
    ));

    final ack = await ackPort.first as _IsolateInitAck;
    ackPort.close();

    if (ack.error != null) throw Exception(ack.error);
    _outputShape = ack.outputShape;
    if (kDebugMode) debugPrint('[DS] Isolate ready + init confirmed');
  }

  /// Stops the current isolate and respawns it after repeated timeouts.
  Future<void> _killAndRespawnIsolate() async {
    if (kDebugMode) debugPrint('[DS] Respawning isolate...');

    final oldSendPort = _isolateSendPort;
    final oldIsolate = _isolate;
    final oldReceivePort = _mainReceivePort;

    _isolateSendPort = null;
    _isolate = null;
    _mainReceivePort = null;
    _isolateBusy = false;

    if (oldSendPort != null) {
      try {
        final shutdownAck = ReceivePort();
        oldSendPort.send(_IsolateShutdown(replyPort: shutdownAck.sendPort));
        await shutdownAck.first
            .timeout(const Duration(milliseconds: 500))
            .catchError((_) => null);
        shutdownAck.close();
      } catch (_) {}
    }

    oldReceivePort?.close();
    oldIsolate?.kill(priority: Isolate.immediate);

    if (kDebugMode) debugPrint('[DS] Old isolate killed, spawning new one...');

    try {
      final modelData = await rootBundle.load(AssetPaths.modelFile);
      await _spawnIsolate(modelData.buffer.asUint8List());
      _consecutiveTimeouts = 0;
      if (kDebugMode) debugPrint('[DS] Isolate respawned successfully');
    } catch (e) {
      debugPrint('[DS] Respawn FAILED: $e');
      _modelLoaded = false;
    }
  }

  bool _isolateBusy = false;

  @override
  Future<List<Map<String, dynamic>>> runInference(
    CameraImage image, {
    required int rotationDegrees,
  }) async {
    if (!_modelLoaded || _isolateSendPort == null) return [];
    if (_isolateBusy) return [];
    _isolateBusy = true;

    ReceivePort? replyPort;
    try {
      final planeBytes = <TransferableTypedData>[
        for (final p in image.planes) TransferableTypedData.fromList([p.bytes]),
      ];
      final rowStrides = image.planes.map((p) => p.bytesPerRow).toList();
      final pixelStrides =
          image.planes.map((p) => p.bytesPerPixel ?? 1).toList();

      replyPort = ReceivePort();
      _isolateSendPort!.send(_InferenceJob(
        replyPort: replyPort.sendPort,
        planeBytes: planeBytes,
        planeRowStrides: rowStrides,
        planePixelStrides: pixelStrides,
        imageWidth: image.width,
        imageHeight: image.height,
        rotationDegrees: rotationDegrees,
        confidenceThreshold: _config.confidenceThreshold,
        iouThreshold: _config.iouThreshold,
        maxDetections: _config.maxDetections,
      ));

      final dynamic result = await replyPort.first.timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () {
          if (kDebugMode) debugPrint('[DS] inference timeout after 2.5s');
          return 'TIMEOUT';
        },
      );

      if (result is String) {
        if (kDebugMode) debugPrint('[DS] isolate signal: $result');
        if (result == 'TIMEOUT') {
          _consecutiveTimeouts++;
          if (_consecutiveTimeouts >= 3) {
            debugPrint('[DS] 3 consecutive timeouts -> respawning isolate');
            await _killAndRespawnIsolate();
            _consecutiveTimeouts = 0;
          } else {
            debugPrint('[DS] timeout #$_consecutiveTimeouts -> skipping frame');
          }
        } else {
          await _killAndRespawnIsolate();
          _consecutiveTimeouts = 0;
        }
        return [];
      }

      _consecutiveTimeouts = 0;
      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
      debugPrint('[DS] exception: $e');
      return [];
    } finally {
      replyPort?.close();
      _isolateBusy = false;
    }
  }

  @override
  Future<void> closeModel() async {
    final oldSendPort = _isolateSendPort;
    final oldIsolate = _isolate;
    final oldReceivePort = _mainReceivePort;

    _isolateSendPort = null;
    _isolate = null;
    _mainReceivePort = null;
    _isolateBusy = false;
    _modelLoaded = false;
    _consecutiveTimeouts = 0;

    if (oldSendPort != null) {
      try {
        final shutdownAck = ReceivePort();
        oldSendPort.send(_IsolateShutdown(replyPort: shutdownAck.sendPort));
        await shutdownAck.first.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {
            debugPrint('[DS] isolate shutdown timeout — force killing');
            return null;
          },
        ).catchError((_) => null);
        shutdownAck.close();
      } catch (_) {}
    }

    oldReceivePort?.close();
    oldIsolate?.kill(priority: Isolate.immediate);

    if (kDebugMode) debugPrint('[DS] model closed, resources freed');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate globals
// These variables live inside the isolate's own memory space.
// ─────────────────────────────────────────────────────────────────────────────

Interpreter? _cachedInterpreter;
Float32List? _cachedTensor;
Uint8List? _cachedOutputBytes;
Float32List? _cachedOutputFloats;
int _cachedOutputLen = 0;

List<String>? _initLabels;
int _initInputSize = 0;
List<int> _initOutputShape = const [];

// FIX: Tracks which delegates have permanently failed so they are never
// retried on subsequent inference calls or isolate respawns.
//
// Previously, the code attempted GPU delegate first, set delegateEnabled=true
// optimistically, then caught no exception because GPU delegate failure
// happens inside Interpreter.fromBuffer (during TFLite's Init/Prepare phase),
// not at the addDelegate() call site. This caused two problems:
//   1. Every respawn retried GPU, reproducing the crash on MTK devices.
//   2. When GPU "partially" delegated nodes then failed, TFLite's plan
//      restoration left CONCATENATION node tensor dimensions corrupted,
//      directly causing the (20 != 40) shape mismatch error.
//
// With this flag, once NNAPI fails the isolate falls back to CPU permanently
// for its lifetime. On respawn, a fresh isolate retries NNAPI (appropriate —
// the failure may have been transient), but GPU is never attempted.
bool _nnApiFailed = false;

/// Entry point for the isolate.
void _isolateEntry(SendPort mainSendPort) {
  final jobPort = ReceivePort();
  mainSendPort.send(jobPort.sendPort);

  jobPort.listen((msg) {
    if (msg is _IsolateInitMsg) {
      _initLabels = msg.labels;
      _initInputSize = msg.inputSize;

      try {
        _cachedInterpreter = _createInterpreter(
          msg.modelBytes.materialize().asUint8List(),
        );

        // Validate that the model's expected input size matches what the app
        // is configured to send. A mismatch here is the root cause of the
        // CONCATENATION shape error (20 != 40) seen in production.
        //
        // Expected input tensor shape: [1, inputSize, inputSize, 3]
        _validateInputShape(_cachedInterpreter!, _initInputSize);

        _initOutputShape = _cachedInterpreter!.getOutputTensor(0).shape;

        msg.ackPort.send(
          _IsolateInitAck(outputShape: _initOutputShape),
        );
      } catch (e) {
        debugPrint('[Isolate] init error: $e');
        msg.ackPort.send(
          _IsolateInitAck(outputShape: const [], error: e.toString()),
        );
      }
    } else if (msg is _IsolateShutdown) {
      try {
        _cachedInterpreter?.close();
        _cachedInterpreter = null;
      } catch (e) {
        debugPrint('[Isolate] error closing interpreter: $e');
      }
      msg.replyPort.send(const _IsolateInitAck(outputShape: []));
      jobPort.close();
      Isolate.exit();
    } else if (msg is _InferenceJob) {
      if (_initLabels == null) {
        msg.replyPort.send('ERROR: not initialized');
        return;
      }
      _processJob(msg);
    }
  });
}

/// Creates an [Interpreter] using the best available delegate.
///
/// Delegate priority:
///   Android: NNAPI → CPU
///   iOS:     Metal → CPU
///   Other:   CPU
///
/// GPU delegate is intentionally excluded on Android. See class-level
/// documentation on [DetectionLocalDatasourceImpl] for full rationale.
///
/// Each attempt wraps [Interpreter.fromBuffer] — not [addDelegate] — because
/// TFLite defers delegate Init/Prepare to interpreter construction. Only at
/// that point does TFLite invoke the delegate's Init and Prepare callbacks,
/// which may fail on unsupported hardware. A try/catch at [addDelegate] will
/// never fire for delegate preparation failures.
Interpreter _createInterpreter(Uint8List modelBytes) {
  if (Platform.isAndroid && !_nnApiFailed) {
    try {
      final options = InterpreterOptions()..useNnApiForAndroid = true;
      final interp = Interpreter.fromBuffer(modelBytes, options: options);
      debugPrint('[Isolate] Delegate: NNAPI');
      return interp;
    } catch (e) {
      debugPrint('[Isolate] NNAPI failed: $e — falling back to CPU');
      // Mark permanently failed for this isolate's lifetime.
      // A fresh isolate (on respawn) will retry NNAPI since it may be
      // a transient driver error, not a permanent hardware limitation.
      _nnApiFailed = true;
    }
  }

  if (Platform.isIOS) {
    try {
      final options = InterpreterOptions()..useMetalDelegateForIOS = true;
      final interp = Interpreter.fromBuffer(modelBytes, options: options);
      debugPrint('[Isolate] Delegate: Metal');
      return interp;
    } catch (e) {
      debugPrint('[Isolate] Metal failed: $e — falling back to CPU');
    }
  }

  // CPU fallback — always succeeds, uses multiple threads for performance.
  final options = InterpreterOptions()..threads = AppConstants.inferenceThreads;
  debugPrint(
      '[Isolate] Delegate: CPU (${AppConstants.inferenceThreads} threads)');
  return Interpreter.fromBuffer(modelBytes, options: options);
}

/// Validates that the interpreter's input tensor shape matches [expectedInputSize].
///
/// The YOLOv8 model must be exported at the same resolution as
/// [AppConstants.inputSize]. A mismatch causes the CONCATENATION node at the
/// feature pyramid neck to receive tensors of incompatible spatial dimensions:
///
///   inputSize / stride = expected spatial dimension
///   e.g. 320 / 16 = 20  (app)  vs  640 / 16 = 40  (model) → crash
///
/// Throwing here — at interpreter creation time — produces a clear error
/// message instead of the cryptic TFLite kernel error that appears at
/// inference time after the shape propagation reaches the concatenation node.
void _validateInputShape(Interpreter interpreter, int expectedInputSize) {
  final inputShape = interpreter.getInputTensor(0).shape;

  // Expected NHWC layout: [batch=1, height, width, channels=3]
  if (inputShape.length != 4) {
    throw StateError(
      '[Isolate] Unexpected input tensor rank: ${inputShape.length} '
      '(expected 4 for NHWC layout). Shape: $inputShape',
    );
  }

  final modelH = inputShape[1];
  final modelW = inputShape[2];

  if (modelH != expectedInputSize || modelW != expectedInputSize) {
    throw StateError(
      '[Isolate] Input size mismatch.\n'
      '  AppConstants.inputSize = $expectedInputSize\n'
      '  Model expects: $modelH×$modelW\n'
      'Fix: either update AppConstants.inputSize to $modelH, '
      'or re-export the model at $expectedInputSize×$expectedInputSize.',
    );
  }

  debugPrint('[Isolate] Input shape validated: $inputShape');
}

void _processJob(_InferenceJob job) {
  try {
    final interpreter = _cachedInterpreter!;

    final planes = <Uint8List>[
      for (final t in job.planeBytes) t.materialize().asUint8List(),
    ];

    final lb = ImageConverter.yuvToLetterboxedFloat32(
      planes: planes,
      rowStrides: job.planeRowStrides,
      pixelStrides: job.planePixelStrides,
      srcWidth: job.imageWidth,
      srcHeight: job.imageHeight,
      inputSize: _initInputSize,
      rotationDegrees: job.rotationDegrees,
      reuseBuffer: _cachedTensor,
    );
    _cachedTensor = lb.inputTensor;

    final inputTensor =
        lb.inputTensor.reshape([1, _initInputSize, _initInputSize, 3]);

    _ensureOutputFlat();
    final outputMap = <int, Object>{0: _cachedOutputBytes!};
    interpreter.runForMultipleInputs([inputTensor], outputMap);

    final results = _parseFlat(
      flat: _cachedOutputFloats!,
      letterbox: lb,
      confidenceThreshold: job.confidenceThreshold,
      iouThreshold: job.iouThreshold,
      maxDetections: job.maxDetections,
    );

    job.replyPort.send(results);
  } catch (e, st) {
    job.replyPort.send('ERROR: $e\n$st');
  }
}

void _ensureOutputFlat() {
  if (_initOutputShape.length < 3) {
    throw StateError('[Isolate] Output shape invalid: $_initOutputShape');
  }
  final needed = _initOutputShape[1] * _initOutputShape[2];
  if (needed <= 0) {
    throw StateError('[Isolate] Output shape produced needed=$needed');
  }
  if (_cachedOutputBytes == null || _cachedOutputLen != needed) {
    _cachedOutputBytes = Uint8List(needed * Float32List.bytesPerElement);
    _cachedOutputFloats = _cachedOutputBytes!.buffer.asFloat32List();
    _cachedOutputLen = needed;
  }
}

List<Map<String, dynamic>> _parseFlat({
  required Float32List flat,
  required LetterboxResult letterbox,
  required double confidenceThreshold,
  required double iouThreshold,
  required int maxDetections,
}) {
  final labels = _initLabels!;
  final inputSize = _initInputSize;
  final shape = _initOutputShape;

  if (shape.length < 3) return [];

  final int dim0 = shape[1];
  final int dim1 = shape[2];
  final bool isTransposed = dim0 < dim1;
  final int numBoxes = isTransposed ? dim1 : dim0;
  final int numChannels = isTransposed ? dim0 : dim1;
  final int classOffset = AppConstants.yoloHasObjectness ? 5 : 4;
  final int availableClasses =
      (numChannels - classOffset).clamp(0, labels.length);

  if (availableClasses <= 0) return [];

  double valueAt(int boxIndex, int channelIndex) {
    if (isTransposed) return flat[channelIndex * numBoxes + boxIndex];
    return flat[boxIndex * numChannels + channelIndex];
  }

  final rawBoxes = <_RawBox>[];

  for (int i = 0; i < numBoxes; i++) {
    final double cx = valueAt(i, 0);
    final double cy = valueAt(i, 1);
    final double bw = valueAt(i, 2);
    final double bh = valueAt(i, 3);
    if (bw <= 0 || bh <= 0) continue;

    final double objectness =
        AppConstants.yoloHasObjectness ? _activateScore(valueAt(i, 4)) : 1.0;
    if (objectness < confidenceThreshold) continue;

    int bestClassId = -1;
    double bestClassScore = 0.0;
    for (int c = 0; c < availableClasses; c++) {
      final double score = _activateScore(valueAt(i, classOffset + c));
      if (score > bestClassScore) {
        bestClassScore = score;
        bestClassId = c;
      }
    }
    if (bestClassId < 0) continue;

    final double finalScore = objectness * bestClassScore;
    if (finalScore < confidenceThreshold) continue;

    final box = ImageConverter.unLetterboxBox(
      cx: cx,
      cy: cy,
      bw: bw,
      bh: bh,
      padLeft: letterbox.padLeft,
      padTop: letterbox.padTop,
      scale: letterbox.scale,
      origWidth: letterbox.origWidth,
      origHeight: letterbox.origHeight,
      inputSize: inputSize,
    );
    if (box.width <= 0 || box.height <= 0) continue;

    rawBoxes.add(_RawBox(
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      score: finalScore,
      classId: bestClassId,
    ));
  }

  if (rawBoxes.length > 100) {
    rawBoxes.sort((a, b) => b.score.compareTo(a.score));
    rawBoxes.removeRange(100, rawBoxes.length);
  }

  final kept = _nms(rawBoxes, iouThreshold);

  return kept.take(maxDetections).map((b) {
    final label =
        b.classId < labels.length ? labels[b.classId] : 'class_${b.classId}';
    return <String, dynamic>{
      'label': label,
      'confidence': b.score,
      'left': b.left,
      'top': b.top,
      'width': b.width,
      'height': b.height,
    };
  }).toList();
}

double _activateScore(double rawScore) {
  if (!AppConstants.yoloOutputLogits) return rawScore;
  return 1.0 / (1.0 + exp(-rawScore));
}

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
  if (iR <= iL || iB <= iT) return 0;
  final inter = (iR - iL) * (iB - iT);
  return inter / (a.width * a.height + b.width * b.height - inter);
}

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

// ─── Cross-isolate message types ─────────────────────────────────────────────

class _IsolateInitMsg {
  final List<String> labels;
  final int inputSize;
  final TransferableTypedData modelBytes;
  final SendPort ackPort;
  const _IsolateInitMsg({
    required this.labels,
    required this.inputSize,
    required this.modelBytes,
    required this.ackPort,
  });
}

class _IsolateInitAck {
  final List<int> outputShape;
  final String? error;
  const _IsolateInitAck({required this.outputShape, this.error});
}

class _IsolateShutdown {
  final SendPort replyPort;
  const _IsolateShutdown({required this.replyPort});
}

class _InferenceJob {
  final SendPort replyPort;
  final List<TransferableTypedData> planeBytes;
  final List<int> planeRowStrides;
  final List<int> planePixelStrides;
  final int imageWidth, imageHeight, rotationDegrees;
  final double confidenceThreshold, iouThreshold;
  final int maxDetections;
  const _InferenceJob({
    required this.replyPort,
    required this.planeBytes,
    required this.planeRowStrides,
    required this.planePixelStrides,
    required this.imageWidth,
    required this.imageHeight,
    required this.rotationDegrees,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.maxDetections,
  });
}
