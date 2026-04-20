import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../../core/config/detection_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/image_converter.dart';
import '../../../../core/models/camera_frame.dart';
import 'detection_local_datasource.dart';

// ── Delegate mode ─────────────────────────────────────────────────────────────

enum _DelegateMode { accelerated, cpu, none }

// ── Isolate message types ─────────────────────────────────────────────────────

class _LoadRequest {
  const _LoadRequest({
    required this.modelBuffer,
    required this.labelsRaw,
    required this.delegateMode,
    required this.numThreads,
  });

  final TransferableTypedData modelBuffer;
  final String labelsRaw;
  final _DelegateMode delegateMode;
  final int numThreads;
}

class _InferenceRequest {
  const _InferenceRequest({
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
    required this.srcWidth,
    required this.srcHeight,
    required this.rotationDegrees,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.maxDetections,
    required this.inputSize,
  });

  final List<Uint8List> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;
  final int srcWidth;
  final int srcHeight;
  final int rotationDegrees;
  final double confidenceThreshold;
  final double iouThreshold;
  final int maxDetections;
  final int inputSize;
}

class _DelegateFailedSignal {
  const _DelegateFailedSignal(this.reason);
  final String reason;
}

// ── Isolate state ─────────────────────────────────────────────────────────────

class _IsolateState {
  Interpreter? interpreter;
  List<String> labels = [];
  bool modelLoaded = false;
  int consecutiveFailures = 0;

  static const int maxConsecutiveFailures = 3;
}

// ── Isolate entry point ───────────────────────────────────────────────────────

void _inferenceEntryPoint(SendPort mainSendPort) {
  final state = _IsolateState();

  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  commandPort.listen((dynamic message) async {
    if (message is _LoadRequest) {
      await _handleLoad(state, message, mainSendPort);
    } else if (message is _InferenceRequest) {
      await _handleInference(state, message, mainSendPort);
    }
  });
}

Future<void> _handleLoad(
  _IsolateState state,
  _LoadRequest req,
  SendPort out,
) async {
  try {
    final bytes = req.modelBuffer.materialize().asUint8List();
    final options = _buildOptions(req.delegateMode, req.numThreads);
    state.interpreter = Interpreter.fromBuffer(bytes, options: options);
    state.labels = req.labelsRaw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    state.modelLoaded = true;
    state.consecutiveFailures = 0;
    out.send(true);
  } catch (e) {
    debugPrint('[Isolate] load failed (delegate=${req.delegateMode}): $e');
    out.send(_DelegateFailedSignal(e.toString()));
  }
}

Future<void> _handleInference(
  _IsolateState state,
  _InferenceRequest req,
  SendPort out,
) async {
  if (!state.modelLoaded || state.interpreter == null) {
    out.send(<Map<String, dynamic>>[]);
    return;
  }
  try {
    final results = _runInference(state, req);
    state.consecutiveFailures = 0;
    out.send(results);
  } catch (e) {
    state.consecutiveFailures++;
    debugPrint('[Isolate] inference error #${state.consecutiveFailures}: $e');
    if (state.consecutiveFailures >= _IsolateState.maxConsecutiveFailures) {
      out.send(_DelegateFailedSignal(e.toString()));
    } else {
      out.send(<Map<String, dynamic>>[]);
    }
  }
}

// ── Delegate construction ─────────────────────────────────────────────────────

InterpreterOptions _buildOptions(_DelegateMode mode, int numThreads) {
  final opts = InterpreterOptions()..threads = numThreads;
  switch (mode) {
    case _DelegateMode.accelerated:
      try {
        opts.addDelegate(GpuDelegateV2());
      } catch (_) {}
    case _DelegateMode.cpu:
      opts.addDelegate(XNNPackDelegate(
        options: XNNPackDelegateOptions(numThreads: numThreads),
      ));
    case _DelegateMode.none:
      break;
  }
  return opts;
}

// ── Inference ─────────────────────────────────────────────────────────────────

List<Map<String, dynamic>> _runInference(
  _IsolateState state,
  _InferenceRequest req,
) {
  final interpreter = state.interpreter!;
  final lb = ImageConverter.yuvToLetterboxedFloat32(
    planes: req.planes,
    rowStrides: req.rowStrides,
    pixelStrides: req.pixelStrides,
    srcWidth: req.srcWidth,
    srcHeight: req.srcHeight,
    inputSize: req.inputSize,
    rotationDegrees: req.rotationDegrees,
  );

  final shape = [1, req.inputSize, req.inputSize, 3];
  interpreter.resizeInputTensor(0, shape);
  interpreter.allocateTensors();
  interpreter.getInputTensor(0).setTo(lb.inputTensor);
  interpreter.invoke();

  final raw = interpreter.getOutputTensor(0).data.buffer.asFloat32List();
  return _decodeAndNms(raw, lb, state.labels, req);
}

List<Map<String, dynamic>> _decodeAndNms(
  Float32List raw,
  LetterboxResult lb,
  List<String> labels,
  _InferenceRequest req,
) {
  final nc = labels.length;
  final na = raw.length ~/ (4 + nc);
  final dets = <Map<String, dynamic>>[];

  for (int a = 0; a < na; a++) {
    final b = a * (4 + nc);
    double best = req.confidenceThreshold;
    int cls = -1;
    for (int c = 0; c < nc; c++) {
      if (raw[b + 4 + c] > best) {
        best = raw[b + 4 + c];
        cls = c;
      }
    }
    if (cls < 0) continue;

    final box = ImageConverter.unLetterboxBox(
      cx: raw[b],
      cy: raw[b + 1],
      bw: raw[b + 2],
      bh: raw[b + 3],
      coordinatesAreNormalized: !AppConstants.yoloOutputLogits,
      padLeft: lb.padLeft,
      padTop: lb.padTop,
      scale: lb.scale,
      origWidth: lb.origWidth,
      origHeight: lb.origHeight,
      inputSize: req.inputSize,
    );

    dets.add({
      'label': labels[cls],
      'confidence': best,
      'left': box.left,
      'top': box.top,
      'width': box.width,
      'height': box.height,
    });
  }
  return _nms(dets, req.iouThreshold, req.maxDetections);
}

List<Map<String, dynamic>> _nms(
  List<Map<String, dynamic>> d,
  double iou,
  int max,
) {
  d.sort((a, b) =>
      (b['confidence'] as double).compareTo(a['confidence'] as double));
  final k = <Map<String, dynamic>>[];
  for (final det in d) {
    if (k.length >= max) break;
    if (k.every((kept) => _iou(det, kept) <= iou)) k.add(det);
  }
  return k;
}

double _iou(Map<String, dynamic> a, Map<String, dynamic> b) {
  final al = a['left'] as double, at = a['top'] as double;
  final ar = al + (a['width'] as double), ab = at + (a['height'] as double);
  final bl = b['left'] as double, bt = b['top'] as double;
  final br = bl + (b['width'] as double), bb = bt + (b['height'] as double);
  final ix = (ar < br ? ar : br) - (al > bl ? al : bl);
  final iy = (ab < bb ? ab : bb) - (at > bt ? at : bt);
  if (ix <= 0 || iy <= 0) return 0;
  final inter = ix * iy;
  return inter / ((ar - al) * (ab - at) + (br - bl) * (bb - bt) - inter);
}

class DetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  DetectionLocalDatasourceImpl(this._detectionConfig);

  final DetectionConfig _detectionConfig;

  Isolate? _isolate;
  SendPort? _toIsolate;

  ReceivePort? _rawPort;
  Stream<dynamic>? _fromIsolate;

  bool _isolateBusy = false;

  Uint8List? _modelBytes;
  String? _labelsRaw;

  _DelegateMode _delegateMode = _DelegateMode.accelerated;
  int _consecutiveAcceleratedFailures = 0;
  int _consecutiveCpuFailures = 0;

  // ── DetectionLocalDatasource ───────────────────────────────────────────────

  @override
  Future<void> loadModel() async {
    await _ensureModelAssets();
    await _spawnAndLoad();
    _clearModelAssets();
  }

  @override
  Future<List<Map<String, dynamic>>> runInference(
    CameraFrame frame, {
    required int rotationDegrees,
  }) async {
    if (_toIsolate == null ||
        _fromIsolate == null ||
        _delegateMode == _DelegateMode.none) {
      return [];
    }
    if (_isolateBusy) return [];

    _isolateBusy = true;

    StreamSubscription<dynamic>? sub;
    var subCancelled = false;
    Future<void> cancelSub() async {
      if (subCancelled) return;
      subCancelled = true;
      await sub?.cancel();
    }

    try {
      final completer = Completer<dynamic>();

      sub = _fromIsolate!.listen((msg) {
        if (!completer.isCompleted) {
          completer.complete(msg);
          unawaited(cancelSub());
        }
      });

      _toIsolate!.send(_InferenceRequest(
        planes: frame.planes,
        rowStrides: frame.rowStrides,
        pixelStrides: frame.pixelStrides,
        srcWidth: frame.width,
        srcHeight: frame.height,
        rotationDegrees: rotationDegrees,
        confidenceThreshold: _detectionConfig.confidenceThreshold,
        iouThreshold: _detectionConfig.iouThreshold,
        maxDetections: _detectionConfig.maxDetections,
        inputSize: AppConstants.inputSize,
      ));

      final result = await completer.future.timeout(
        const Duration(milliseconds: AppConstants.inferenceTimeoutMs),
        onTimeout: () {
          unawaited(cancelSub());
          return <Map<String, dynamic>>[];
        },
      );

      if (result is _DelegateFailedSignal) {
        debugPrint('[Datasource] delegate failed: ${result.reason}');
        await _handleDelegateFailure();
        return [];
      }

      if (_delegateMode == _DelegateMode.accelerated) {
        _consecutiveAcceleratedFailures = 0;
      } else {
        _consecutiveCpuFailures = 0;
      }

      return (result as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[Datasource] runInference error: $e');
      return [];
    } finally {
      await cancelSub();
      _isolateBusy = false;
    }
  }

  @override
  Future<void> closeModel() async {
    _isolateBusy = false;
    _killIsolate();
    _clearModelAssets();
    _delegateMode = _DelegateMode.accelerated;
    _consecutiveAcceleratedFailures = 0;
    _consecutiveCpuFailures = 0;
  }

  // ── Delegate failure / downgrade ──────────────────────────────────────────

  Future<void> _handleDelegateFailure() async {
    if (_delegateMode == _DelegateMode.accelerated) {
      _consecutiveAcceleratedFailures++;
      if (_consecutiveAcceleratedFailures >=
          AppConstants.maxConsecutiveAcceleratedFailures) {
        debugPrint('[Datasource] GPU failed — downgrading to XNNPack CPU');
        _delegateMode = _DelegateMode.cpu;
        _consecutiveAcceleratedFailures = 0;
        _killIsolate();
        await _spawnAndLoad();
        _clearModelAssets();
      }
    } else if (_delegateMode == _DelegateMode.cpu) {
      _consecutiveCpuFailures++;
      if (_consecutiveCpuFailures >= AppConstants.maxConsecutiveCpuFailures) {
        debugPrint('[Datasource] CPU failed — disabling inference');
        _delegateMode = _DelegateMode.none;
        _killIsolate();
        _clearModelAssets();
      }
    }
  }

  // ── Asset helpers ──────────────────────────────────────────────────────────

  /// Loads model bytes and labels from disk if they are not already cached.
  /// Called before every _spawnAndLoad() to support delegate respawns after
  /// the heap copy was cleared by _clearModelAssets().
  Future<void> _ensureModelAssets() async {
    // prefer_conditional_assignment: use ??= so the async expression is only
    // evaluated when the field is actually null.
    _modelBytes ??= (await rootBundle.load(AppConstants.modelFileName))
        .buffer
        .asUint8List();
    _labelsRaw ??= await rootBundle.loadString(AppConstants.labelsFileName);
  }

  /// Nulls both asset fields to release their memory from the Dart heap.
  void _clearModelAssets() {
    _modelBytes = null;
    _labelsRaw = null;
  }

  // ── Isolate lifecycle ──────────────────────────────────────────────────────

  Future<void> _spawnAndLoad() async {
    _killIsolate();

    // Reload assets from disk if they were cleared after a previous load.
    await _ensureModelAssets();

    _rawPort = ReceivePort();
    _fromIsolate = _rawPort!.asBroadcastStream();

    _isolate = await Isolate.spawn(
      _inferenceEntryPoint,
      _rawPort!.sendPort,
      debugName: 'SafeVision-Inference',
      errorsAreFatal: false,
    );

    _toIsolate = await _fromIsolate!.first as SendPort;

    final ack = await _sendLoad();

    if (ack is _DelegateFailedSignal) {
      debugPrint('[Datasource] model load failed: ${ack.reason}');
      await _handleDelegateFailure();
    }
  }

  Future<dynamic> _sendLoad() async {
    final completer = Completer<dynamic>();

    StreamSubscription<dynamic>? sub;
    var subCancelled = false;
    Future<void> cancelSub() async {
      if (subCancelled) return;
      subCancelled = true;
      await sub?.cancel();
    }

    try {
      sub = _fromIsolate!.listen((msg) {
        if (!completer.isCompleted) {
          completer.complete(msg);
          unawaited(cancelSub());
        }
      });

      _toIsolate!.send(_LoadRequest(
        modelBuffer: TransferableTypedData.fromList([_modelBytes!]),
        labelsRaw: _labelsRaw!,
        delegateMode: _delegateMode,
        numThreads: AppConstants.inferenceThreads,
      ));

      return completer.future.timeout(
        const Duration(milliseconds: AppConstants.inferenceTimeoutMs),
        onTimeout: () {
          unawaited(cancelSub());
          return _DelegateFailedSignal('load timeout');
        },
      );
    } finally {
      await cancelSub();
    }
  }

  void _killIsolate() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _rawPort?.close();
    _rawPort = null;
    _fromIsolate = null;
    _toIsolate = null;
    _isolateBusy = false;
  }
}
