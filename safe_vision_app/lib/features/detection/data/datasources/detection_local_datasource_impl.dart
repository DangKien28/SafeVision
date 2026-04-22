import 'dart:isolate';
import 'dart:math';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection_local_datasource.dart';
import '../../../../core/config/detection_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_paths.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/services/camera_service.dart' show CameraFrame;
import '../../../../core/utils/image_converter.dart';

class DetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  DetectionLocalDatasourceImpl(this._config);

  final DetectionConfig _config;

  List<String> _labels = [];
  List<int> _outputShape = [];
  bool _modelLoaded = false;

  Uint8List? _cachedModelBytes;
  bool _allowNnapi = true;

  Isolate? _isolate;
  SendPort? _isolateSendPort;

  static const int _maxConsecutiveTimeouts = 2;
  int _consecutiveTimeouts = 0;
  bool _isolateBusy = false;

  /// Tracks the duration of the most recent successful inference for
  /// performance monitoring. Zero until the first successful inference.
  int _lastInferenceMs = 0;
  int get lastInferenceMs => _lastInferenceMs;

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
      _cachedModelBytes = modelData.buffer.asUint8List();

      await _spawnIsolate(_cachedModelBytes!);

      if (kDebugMode) {
        debugPrint('[DS] Model loaded — '
            'delegate=${_allowNnapi ? "NNAPI→XNNPack→CPU" : "XNNPack→CPU"} '
            'threads=${AppConstants.inferenceThreads}');
        debugPrint('[DS]   output=$_outputShape  labels=${_labels.length}');
      }

      _modelLoaded = true;
    } catch (e, st) {
      debugPrint('[DS] loadModel FAILED: $e\n$st');
      throw ModelNotFoundException('Cannot load model: $e');
    }
  }

  Future<void> _spawnIsolate(Uint8List modelBytes) async {
    final handshakePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, handshakePort.sendPort);
    _isolateSendPort = await handshakePort.first as SendPort;
    handshakePort.close();

    final ackPort = ReceivePort();
    _isolateSendPort!.send(_IsolateInitMsg(
      labels: List.unmodifiable(_labels),
      inputSize: AppConstants.inputSize,
      modelBytes: TransferableTypedData.fromList([modelBytes]),
      ackPort: ackPort.sendPort,
      allowNnapi: _allowNnapi,
    ));

    final ack = await ackPort.first as _IsolateInitAck;
    ackPort.close();

    if (ack.error != null) throw Exception(ack.error);
    _outputShape = ack.outputShape;

    if (kDebugMode) debugPrint('[DS] Isolate ready — running warmup probe...');

    if (_allowNnapi && Platform.isAndroid) {
      final passed = await _runWarmupProbe();
      if (!passed) {
        debugPrint('[DS] WARMUP PROBE FAILED: NNAPI exceeded '
            '${AppConstants.warmupTimeoutMs}ms — switching to XNNPack/CPU.');
        _allowNnapi = false;
        await _killIsolateOnly();
        await _spawnIsolate(modelBytes);
      } else {
        if (kDebugMode) debugPrint('[DS] WARMUP PROBE PASSED: NNAPI ok');
      }
    } else {
      if (kDebugMode) {
        debugPrint('[DS] Warmup probe skipped '
            '(${Platform.isAndroid ? "CPU-only mode" : "non-Android"})');
      }
    }
  }

  Future<bool> _runWarmupProbe() async {
    if (_isolateSendPort == null) return false;
    final size = AppConstants.inputSize;
    final dummy = Float32List(size * size * 3);
    final replyPort = ReceivePort();
    _isolateSendPort!.send(_WarmupProbeMsg(
      replyPort: replyPort.sendPort,
      dummyTensor: TransferableTypedData.fromList([dummy]),
      inputSize: size,
    ));
    bool passed = false;
    try {
      final r = await replyPort.first.timeout(
        Duration(milliseconds: AppConstants.warmupTimeoutMs),
        onTimeout: () => 'TIMEOUT',
      );
      passed = r != 'TIMEOUT';
    } catch (_) {
    } finally {
      replyPort.close();
    }
    return passed;
  }

  Future<void> _killIsolateOnly() async {
    final sp = _isolateSendPort;
    final iso = _isolate;
    _isolateSendPort = null;
    _isolate = null;
    _isolateBusy = false;
    if (sp != null) {
      try {
        final ack = ReceivePort();
        sp.send(_IsolateShutdown(replyPort: ack.sendPort));
        await ack.first
            .timeout(const Duration(milliseconds: 300))
            .catchError((_) => null);
        ack.close();
      } catch (_) {}
    }
    iso?.kill(priority: Isolate.immediate);
    if (kDebugMode) debugPrint('[DS] Old isolate killed');
  }

  Future<void> _killAndRespawnIsolate() async {
    if (kDebugMode) {
      debugPrint('[DS] Respawning isolate '
          '(allowNnapi=$_allowNnapi, '
          'consecutiveTimeouts=$_consecutiveTimeouts)...');
    }
    await _killIsolateOnly();
    try {
      if (_cachedModelBytes == null) {
        final d = await rootBundle.load(AssetPaths.modelFile);
        _cachedModelBytes = d.buffer.asUint8List();
      }
      await _spawnIsolate(_cachedModelBytes!);
      _consecutiveTimeouts = 0;
      if (kDebugMode) {
        debugPrint('[DS] Isolate respawned — '
            'delegate: ${_allowNnapi ? "NNAPI" : "XNNPack/CPU"}');
      }
    } catch (e) {
      debugPrint('[DS] Respawn FAILED: $e');
      _modelLoaded = false;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> runInference(
    CameraFrame frame, {
    required int rotationDegrees,
  }) async {
    if (!_modelLoaded || _isolateSendPort == null) return [];
    if (_isolateBusy) return [];
    _isolateBusy = true;

    ReceivePort? replyPort;
    final sw = Stopwatch()..start();

    try {
      final planeBytes = <TransferableTypedData>[
        for (final p in frame.planes) TransferableTypedData.fromList([p]),
      ];

      replyPort = ReceivePort();
      _isolateSendPort!.send(_InferenceJob(
        replyPort: replyPort.sendPort,
        planeBytes: planeBytes,
        planeRowStrides: frame.rowStrides,
        planePixelStrides: frame.pixelStrides,
        imageWidth: frame.width,
        imageHeight: frame.height,
        rotationDegrees: rotationDegrees,
        confidenceThreshold: _config.confidenceThreshold,
        iouThreshold: _config.iouThreshold,
        maxDetections: _config.maxDetections,
      ));

      // FIX RC-1: Use AppConstants.inferenceTimeoutMs (now 5000ms).
      // The old hardcoded 4000ms caused false timeouts at 2640ms inference
      // + GC jitter, triggering unnecessary isolate respawns.
      final dynamic result = await replyPort.first.timeout(
        Duration(milliseconds: AppConstants.inferenceTimeoutMs),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[DS] inference timeout after '
                '${AppConstants.inferenceTimeoutMs}ms '
                '(elapsed: ${sw.elapsedMilliseconds}ms)');
          }
          return 'TIMEOUT';
        },
      );

      if (result is String) {
        if (result == 'TIMEOUT') {
          _consecutiveTimeouts++;
          if (_consecutiveTimeouts >= _maxConsecutiveTimeouts) {
            if (_allowNnapi) {
              debugPrint('[DS] $_maxConsecutiveTimeouts timeouts on NNAPI — '
                  'switching to XNNPack/CPU.');
              _allowNnapi = false;
            } else {
              debugPrint(
                  '[DS] $_maxConsecutiveTimeouts timeouts on XNNPack/CPU — '
                  'device may be thermally throttled '
                  '(${AppConstants.inputSize}×${AppConstants.inputSize} input).');
            }
            await _killAndRespawnIsolate();
          } else {
            debugPrint('[DS] timeout #$_consecutiveTimeouts — skipping frame');
          }
        } else {
          // 'ERROR:...' string from isolate
          debugPrint('[DS] isolate error: $result');
          if (_allowNnapi) _allowNnapi = false;
          await _killAndRespawnIsolate();
          _consecutiveTimeouts = 0;
        }
        return [];
      }

      sw.stop();
      _lastInferenceMs = sw.elapsedMilliseconds;
      _consecutiveTimeouts = 0;

      if (kDebugMode && _lastInferenceMs > 1000) {
        debugPrint('[DS] slow inference: ${_lastInferenceMs}ms '
            '(delegate: ${_allowNnapi ? "NNAPI" : "XNNPack/CPU"})');
      }

      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
      debugPrint('[DS] runInference exception: $e');
      return [];
    } finally {
      replyPort?.close();
      _isolateBusy = false;
    }
  }

  @override
  Future<void> closeModel() async {
    final sp = _isolateSendPort;
    final iso = _isolate;
    _isolateSendPort = null;
    _isolate = null;
    _isolateBusy = false;
    _modelLoaded = false;
    _consecutiveTimeouts = 0;
    _lastInferenceMs = 0;

    if (sp != null) {
      try {
        final ack = ReceivePort();
        sp.send(_IsolateShutdown(replyPort: ack.sendPort));
        await ack.first.timeout(const Duration(milliseconds: 500),
            onTimeout: () {
          debugPrint('[DS] isolate shutdown timeout — force killing');
          return null;
        }).catchError((_) => null);
        ack.close();
      } catch (_) {}
    }
    iso?.kill(priority: Isolate.immediate);
    if (kDebugMode) debugPrint('[DS] model closed');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate globals (top-level to avoid SendPort serialisation)
// ─────────────────────────────────────────────────────────────────────────────

Interpreter? _cachedInterpreter;
Float32List? _cachedTensor;
Uint8List? _cachedOutputBytes;
Float32List? _cachedOutputFloats;
int _cachedOutputLen = 0;

List<String>? _initLabels;
int _initInputSize = 0;
List<int> _initOutputShape = const [];

bool _isolateAllowNnapi = true;
bool _nnApiFailed = false;

void _isolateEntry(SendPort mainSendPort) {
  final jobPort = ReceivePort();
  mainSendPort.send(jobPort.sendPort);

  jobPort.listen((msg) {
    if (msg is _IsolateInitMsg) {
      _initLabels = msg.labels;
      _initInputSize = msg.inputSize;
      _isolateAllowNnapi = msg.allowNnapi;
      try {
        _cachedInterpreter =
            _createInterpreter(msg.modelBytes.materialize().asUint8List());
        _validateInputShape(_cachedInterpreter!, _initInputSize);
        _initOutputShape = _cachedInterpreter!.getOutputTensor(0).shape;
        msg.ackPort.send(_IsolateInitAck(outputShape: _initOutputShape));
      } catch (e) {
        debugPrint('[Isolate] init error: $e');
        msg.ackPort
            .send(_IsolateInitAck(outputShape: const [], error: e.toString()));
      }
    } else if (msg is _WarmupProbeMsg) {
      _handleWarmupProbe(msg);
    } else if (msg is _IsolateShutdown) {
      try {
        _cachedInterpreter?.close();
        _cachedInterpreter = null;
      } catch (_) {}
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

void _handleWarmupProbe(_WarmupProbeMsg msg) {
  try {
    final interp = _cachedInterpreter;
    if (interp == null) {
      msg.replyPort.send('ERROR: no interpreter');
      return;
    }
    final size = msg.inputSize;
    final dummy = msg.dummyTensor
        .materialize()
        .asFloat32List()
        .reshape([1, size, size, 3]);
    _ensureOutputFlat();
    final outputMap = <int, Object>{0: _cachedOutputBytes!};
    interp.runForMultipleInputs([dummy], outputMap);
    msg.replyPort.send('OK');
  } catch (e) {
    debugPrint('[Isolate] warmup probe error: $e');
    msg.replyPort.send('ERROR: $e');
  }
}

/// Delegate priority order:
///   Android (allowNnapi=true):   NNAPI → XNNPack → CPU (explicit threads)
///   Android (allowNnapi=false):  XNNPack → CPU (explicit threads)
///   iOS:                         Metal → XNNPack → CPU
Interpreter _createInterpreter(Uint8List modelBytes) {
  // ── NNAPI (Android only, when enabled) ────────────────────────────────────
  if (Platform.isAndroid && _isolateAllowNnapi && !_nnApiFailed) {
    try {
      final opts = InterpreterOptions()..useNnApiForAndroid = true;
      final interp = Interpreter.fromBuffer(modelBytes, options: opts);
      debugPrint('[Isolate] Delegate: NNAPI');
      return interp;
    } catch (e) {
      debugPrint('[Isolate] NNAPI unavailable: $e → trying XNNPack');
      _nnApiFailed = true;
    }
  }

  // ── Metal (iOS) ───────────────────────────────────────────────────────────
  if (Platform.isIOS) {
    try {
      final opts = InterpreterOptions()..useMetalDelegateForIOS = true;
      final interp = Interpreter.fromBuffer(modelBytes, options: opts);
      debugPrint('[Isolate] Delegate: Metal');
      return interp;
    } catch (e) {
      debugPrint('[Isolate] Metal unavailable: $e → trying XNNPack');
    }
  }

  // ── XNNPack (cross-platform NEON/SIMD, 1.5–2.5× faster than plain CPU) ───
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final delegate = XNNPackDelegate(
        options:
            XNNPackDelegateOptions(numThreads: AppConstants.inferenceThreads),
      );
      final opts = InterpreterOptions()..addDelegate(delegate);
      final interp = Interpreter.fromBuffer(modelBytes, options: opts);
      debugPrint('[Isolate] Delegate: XNNPack '
          '(${AppConstants.inferenceThreads} threads)');
      return interp;
    } catch (e) {
      debugPrint('[Isolate] XNNPack unavailable: $e → CPU fallback');
    }
  }

  // ── Plain CPU with explicit thread count ──────────────────────────────────
  // FIX: always set thread count even on the fallback path.
  final opts = InterpreterOptions()..threads = AppConstants.inferenceThreads;
  debugPrint('[Isolate] Delegate: CPU '
      '(${AppConstants.inferenceThreads} threads)');
  return Interpreter.fromBuffer(modelBytes, options: opts);
}

void _validateInputShape(Interpreter interpreter, int expectedInputSize) {
  final s = interpreter.getInputTensor(0).shape;
  if (s.length != 4) {
    throw StateError('[Isolate] Unexpected input rank ${s.length}: $s');
  }
  if (s[1] != expectedInputSize || s[2] != expectedInputSize) {
    throw StateError(
        '[Isolate] Input mismatch: app expects $expectedInputSize, '
        'model expects ${s[1]}×${s[2]}. Update AppConstants.inputSize.');
  }
  debugPrint('[Isolate] Input shape validated: $s');
}

void _processJob(_InferenceJob job) {
  try {
    final interp = _cachedInterpreter!;
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
    interp.runForMultipleInputs([inputTensor], outputMap);

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
    throw StateError('[Isolate] Output shape gives needed=$needed — '
        'model output shape is malformed: $_initOutputShape');
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
  final int avail = (numChannels - classOffset).clamp(0, labels.length);
  if (avail <= 0) return [];

  double at(int b, int c) =>
      isTransposed ? flat[c * numBoxes + b] : flat[b * numChannels + c];

  final rawBoxes = <_RawBox>[];
  for (int i = 0; i < numBoxes; i++) {
    final cx = at(i, 0);
    final cy = at(i, 1);
    final bw = at(i, 2);
    final bh = at(i, 3);
    if (bw <= 0 || bh <= 0) continue;

    final obj = AppConstants.yoloHasObjectness ? _sig(at(i, 4)) : 1.0;
    if (obj < confidenceThreshold) continue;

    int bestId = -1;
    double bestScore = 0;
    for (int c = 0; c < avail; c++) {
      final s = _sig(at(i, classOffset + c));
      if (s > bestScore) {
        bestScore = s;
        bestId = c;
      }
    }
    if (bestId < 0) continue;

    final score = obj * bestScore;
    if (score < confidenceThreshold) continue;

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
      score: score,
      classId: bestId,
    ));
  }

  if (rawBoxes.length > 100) {
    rawBoxes.sort((a, b) => b.score.compareTo(a.score));
    rawBoxes.removeRange(100, rawBoxes.length);
  }

  return _nms(rawBoxes, iouThreshold)
      .take(maxDetections)
      .map((b) => <String, dynamic>{
            'label': b.classId < labels.length
                ? labels[b.classId]
                : 'class_${b.classId}',
            'confidence': b.score,
            'left': b.left,
            'top': b.top,
            'width': b.width,
            'height': b.height,
          })
      .toList();
}

double _sig(double v) =>
    AppConstants.yoloOutputLogits ? 1.0 / (1.0 + exp(-v)) : v;

List<_RawBox> _nms(List<_RawBox> boxes, double iouThreshold) {
  boxes.sort((a, b) => b.score.compareTo(a.score));
  final result = <_RawBox>[];
  for (final box in boxes) {
    // Use class-agnostic NMS so one physical object does not survive as
    // multiple boxes when the model oscillates between nearby labels.
    if (result.every((kept) => _iou(box, kept) <= iouThreshold)) {
      result.add(box);
    }
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

// ── Message classes (all must be const-constructable for isolate safety) ────

class _IsolateInitMsg {
  final List<String> labels;
  final int inputSize;
  final TransferableTypedData modelBytes;
  final SendPort ackPort;
  final bool allowNnapi;
  const _IsolateInitMsg({
    required this.labels,
    required this.inputSize,
    required this.modelBytes,
    required this.ackPort,
    required this.allowNnapi,
  });
}

class _IsolateInitAck {
  final List<int> outputShape;
  final String? error;
  const _IsolateInitAck({required this.outputShape, this.error});
}

class _WarmupProbeMsg {
  final SendPort replyPort;
  final TransferableTypedData dummyTensor;
  final int inputSize;
  const _WarmupProbeMsg({
    required this.replyPort,
    required this.dummyTensor,
    required this.inputSize,
  });
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
