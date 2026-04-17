import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

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

/// Sent from the isolate to the main isolate when a delegate fails.
class _DelegateFailedSignal {
  const _DelegateFailedSignal(this.reason);
  final String reason;
}

// ── Isolate state (encapsulated — no top-level globals) ───────────────────────

/// All mutable state inside the worker isolate.
///
/// Stored as a local variable in [_inferenceEntryPoint], not as a global, so
/// respawned isolates always start with a clean slate.
class _IsolateState {
  Interpreter? interpreter;
  List<String> labels = [];
  bool modelLoaded = false;
  int consecutiveFailures = 0;

  static const int maxConsecutiveFailures = 3;
}

// ── Isolate entry point ───────────────────────────────────────────────────────

/// All mutable state is local — zero globals.
///
/// Communication pattern:
///   1. Main creates a [ReceivePort] and spawns this isolate with its
///      [SendPort] as [mainSendPort].
///   2. Isolate creates its own [ReceivePort], sends [SendPort] back
///      to main (handshake).
///   3. Both sides then use the exchanged ports for all future messages.
///      Main → isolate: _LoadRequest / _InferenceRequest
///      Isolate → main: List<Map<String,dynamic>> / _DelegateFailedSignal / bool
void _inferenceEntryPoint(SendPort mainSendPort) {
  final state = _IsolateState();

  // Step 2: send our command port back to main.
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
    out.send(true); // load success
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
        // GpuDelegateV2 is constructed with default options to avoid
        // Avoids dependency on GPU enum names that differ across tflite_flutter versions.
        opts.addDelegate(GpuDelegateV2());
      } catch (_) {
        // GPU unavailable on this device — XNNPack will be used instead.
      }
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

// ── DetectionLocalDatasourceImpl ──────────────────────────────────────────────

/// Runs YOLOv8 inference in a dedicated isolate with automatic GPU → CPU
/// delegate downgrade.
///
/// ## Isolate communication — BUG FIX
///
/// ### The bug in v1 / v2
///
/// `ReceivePort` is a **single-subscription** stream.  Calling `.first`
/// on it consumes the subscription **and closes the port**.  The previous
/// implementation:
///
/// ```dart
/// final bootstrapPort = ReceivePort();
/// Isolate.spawn(_inferenceEntryPoint, bootstrapPort.sendPort);
/// _toIsolate = await bootstrapPort.first as SendPort;  // closes bootstrapPort!
/// bootstrapPort.close();
///
/// _fromIsolate = ReceivePort();  // NEW port — isolate knows nothing about it
/// ```
///
/// After this, the isolate continued sending results to
/// `bootstrapPort.sendPort` (its `mainSendPort`), but that port was already
/// closed.  Every inference response was silently discarded.
///
/// ### The fix
///
/// We keep the original `ReceivePort` open and convert it to a **broadcast
/// stream** (`asBroadcastStream()`).  This allows:
///   - `.first` to read the handshake message without closing the stream.
///   - All subsequent messages (inference results, delegate-failed signals)
///     to arrive on the same port — which the isolate already knows about.
///
/// One-shot `StreamSubscription`s inside [runInference] pick up each reply
/// without interfering with each other.
class DetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  DetectionLocalDatasourceImpl();

  Isolate? _isolate;
  SendPort? _toIsolate;

  // BUG FIX: kept open for the full isolate lifetime; converted to broadcast
  // so multiple one-shot listeners can attach without cancelling each other.
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
    final data = await rootBundle.load(AppConstants.modelFileName);
    _modelBytes = data.buffer.asUint8List();
    _labelsRaw = await rootBundle.loadString(AppConstants.labelsFileName);
    await _spawnAndLoad();
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

    try {
      final completer = Completer<dynamic>();

      // One-shot listener: resolves the completer on the very next message
      // from the isolate, then cancels itself.
      late StreamSubscription<dynamic> sub;
      sub = _fromIsolate!.listen((msg) {
        if (!completer.isCompleted) {
          completer.complete(msg);
          sub.cancel();
        }
      });

      _toIsolate!.send(_InferenceRequest(
        planes: frame.planes,
        rowStrides: frame.rowStrides,
        pixelStrides: frame.pixelStrides,
        srcWidth: frame.width,
        srcHeight: frame.height,
        rotationDegrees: rotationDegrees,
        confidenceThreshold: AppConstants.confidenceThreshold,
        iouThreshold: AppConstants.iouThreshold,
        maxDetections: AppConstants.maxDetections,
        inputSize: AppConstants.inputSize,
      ));

      final result = await completer.future.timeout(
        const Duration(milliseconds: AppConstants.inferenceTimeoutMs),
        onTimeout: () {
          sub.cancel();
          return <Map<String, dynamic>>[];
        },
      );

      if (result is _DelegateFailedSignal) {
        debugPrint('[Datasource] delegate failed: ${result.reason}');
        await _handleDelegateFailure();
        return [];
      }

      // Reset consecutive failure counters on success.
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
      // Unconditional — the camera stream must never permanently stall.
      _isolateBusy = false;
    }
  }

  @override
  Future<void> closeModel() async {
    _isolateBusy = false;
    _killIsolate();
    _modelBytes = null;
    _labelsRaw = null;
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
      }
    } else if (_delegateMode == _DelegateMode.cpu) {
      _consecutiveCpuFailures++;
      if (_consecutiveCpuFailures >=
          AppConstants.maxConsecutiveCpuFailures) {
        debugPrint('[Datasource] CPU failed — disabling inference');
        _delegateMode = _DelegateMode.none;
        _killIsolate();
      }
    }
  }

  // ── Isolate lifecycle ──────────────────────────────────────────────────────

  Future<void> _spawnAndLoad() async {
    _killIsolate();

    // BUG FIX: create ONE port, keep it open, convert to broadcast stream.
    // The isolate sends ALL messages to this port's sendPort (its mainSendPort).
    _rawPort = ReceivePort();
    // asBroadcastStream() lets multiple one-shot listeners attach over time
    // without each one cancelling the others.
    _fromIsolate = _rawPort!.asBroadcastStream();

    _isolate = await Isolate.spawn(
      _inferenceEntryPoint,
      _rawPort!.sendPort, // isolate sends everything here
      debugName: 'SafeVision-Inference',
      errorsAreFatal: false,
    );

    // Handshake: isolate sends its command SendPort as first message.
    _toIsolate = await _fromIsolate!.first as SendPort;
    // Do NOT close _rawPort — it must stay open for inference replies.

    // Load the model in the isolate and wait for the ack.
    final ack = await _sendLoad();

    if (ack is _DelegateFailedSignal) {
      debugPrint('[Datasource] model load failed: ${ack.reason}');
      await _handleDelegateFailure();
    }
  }

  Future<dynamic> _sendLoad() async {
    final completer = Completer<dynamic>();

    late StreamSubscription<dynamic> sub;
    sub = _fromIsolate!.listen((msg) {
      if (!completer.isCompleted) {
        completer.complete(msg);
        sub.cancel();
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
        sub.cancel();
        return _DelegateFailedSignal('load timeout');
      },
    );
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