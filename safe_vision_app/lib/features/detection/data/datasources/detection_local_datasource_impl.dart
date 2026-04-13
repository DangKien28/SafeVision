import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../../core/config/detection_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_paths.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/models/camera_frame.dart';
import '../../../../core/utils/image_converter.dart';
import 'detection_local_datasource.dart';

class DetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  DetectionLocalDatasourceImpl(this._config);

  final DetectionConfig _config;

  List<String> _labels = const [];
  List<int> _outputShape = const [];
  Uint8List? _cachedModelBytes;

  Isolate? _isolate;
  SendPort? _isolateSendPort;

  bool _modelLoaded = false;
  bool _isolateBusy = false;
  bool _allowAcceleration = true;
  bool _isolateUsesAcceleration = false;
  int _consecutiveFailures = 0;
  int _lastInferenceMs = 0;
  String _delegateName = 'uninitialized';

  int get lastInferenceMs => _lastInferenceMs;

  @override
  Future<void> loadModel() async {
    if (_modelLoaded) {
      debugPrint('[DS] loadModel: already loaded');
      return;
    }

    try {
      _allowAcceleration = true;
      final labelsRaw = await rootBundle.loadString(AssetPaths.labels);
      _labels = labelsRaw
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);

      final modelData = await rootBundle.load(AssetPaths.modelFile);
      _cachedModelBytes = modelData.buffer.asUint8List();

      await _spawnIsolate(_cachedModelBytes!);
      _modelLoaded = true;

      if (kDebugMode) {
        debugPrint('[DS] model ready: delegate=$_delegateName '
            'accelerated=$_isolateUsesAcceleration '
            'output=$_outputShape '
            'labels=${_labels.length}');
      }
    } catch (error, stackTrace) {
      debugPrint('[DS] loadModel failed: $error\n$stackTrace');
      throw ModelNotFoundException('Cannot load model: $error');
    }
  }

  Future<void> _spawnIsolate(Uint8List modelBytes) async {
    final handshakePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, handshakePort.sendPort);
    _isolateSendPort = await handshakePort.first as SendPort;
    handshakePort.close();

    final replyPort = ReceivePort();
    _isolateSendPort!.send(
      _IsolateInitMessage(
        labels: List.unmodifiable(_labels),
        inputSize: AppConstants.inputSize,
        modelBytes: TransferableTypedData.fromList([modelBytes]),
        allowAcceleration: _allowAcceleration,
        replyPort: replyPort.sendPort,
      ),
    );

    final ack = await replyPort.first as _IsolateInitAck;
    replyPort.close();

    if (ack.error != null) {
      await _shutdownIsolate();
      throw StateError(ack.error!);
    }

    _outputShape = ack.outputShape;
    _delegateName = ack.delegateName;
    _isolateUsesAcceleration = ack.isAccelerated;
    _consecutiveFailures = 0;
  }

  Future<void> _shutdownIsolate() async {
    final isolateSendPort = _isolateSendPort;
    final isolate = _isolate;

    _isolateSendPort = null;
    _isolate = null;
    _isolateBusy = false;
    _isolateUsesAcceleration = false;
    _delegateName = 'stopped';
    _outputShape = const [];

    if (isolateSendPort != null) {
      final replyPort = ReceivePort();
      try {
        isolateSendPort.send(_IsolateShutdown(replyPort: replyPort.sendPort));
        await replyPort.first.timeout(const Duration(milliseconds: 500));
      } catch (_) {
      } finally {
        replyPort.close();
      }
    }

    isolate?.kill(priority: Isolate.immediate);
  }

  Future<void> _respawnIsolate({required bool disableAcceleration}) async {
    if (disableAcceleration) {
      _allowAcceleration = false;
    }

    await _shutdownIsolate();
    final modelBytes = _cachedModelBytes;
    if (modelBytes == null) {
      _modelLoaded = false;
      return;
    }

    try {
      await _spawnIsolate(modelBytes);
      if (kDebugMode) {
        debugPrint('[DS] isolate respawned: delegate=$_delegateName');
      }
    } catch (error, stackTrace) {
      _modelLoaded = false;
      debugPrint('[DS] isolate respawn failed: $error\n$stackTrace');
    }
  }

  Future<String> _handleInferenceFailure(String reason) async {
    _consecutiveFailures++;

    final failureLimit = _isolateUsesAcceleration
        ? AppConstants.maxConsecutiveAcceleratedFailures
        : AppConstants.maxConsecutiveCpuFailures;

    if (kDebugMode) {
      debugPrint('[DS] inference failure #$_consecutiveFailures '
          '(delegate=$_delegateName): $reason');
    }

    if (_consecutiveFailures < failureLimit) {
      return reason;
    }

    final shouldDisableAcceleration =
        _isolateUsesAcceleration && _allowAcceleration;
    _consecutiveFailures = 0;
    await _respawnIsolate(disableAcceleration: shouldDisableAcceleration);

    if (_modelLoaded && _isolateSendPort != null) {
      return '$reason. Inference engine restarted.';
    }
    return '$reason. Inference engine restart failed.';
  }

  @override
  Future<List<Map<String, dynamic>>> runInference(
    CameraFrame frame, {
    required int rotationDegrees,
  }) async {
    if (!_modelLoaded || _isolateSendPort == null) {
      throw const InferenceException('Inference engine is unavailable');
    }

    // BACKPRESSURE STRATEGY applied here - single thread lock
    if (_isolateBusy) return const [];

    _isolateBusy = true;
    ReceivePort? replyPort;

    try {
      final planeBytes = <TransferableTypedData>[
        for (final plane in frame.planes)
          TransferableTypedData.fromList([plane]),
      ];

      replyPort = ReceivePort();
      _isolateSendPort!.send(
        _InferenceJob(
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
        ),
      );

      final result = await replyPort.first.timeout(
        Duration(milliseconds: AppConstants.inferenceTimeoutMs),
      );

      if (result is _InferenceResult) {
        _lastInferenceMs = result.totalLatencyMs;
        _consecutiveFailures = 0;
        if (kDebugMode && _lastInferenceMs > 1000) {
          debugPrint(
            '[DS] slow inference: ${_lastInferenceMs}ms '
            '(delegate=$_delegateName)',
          );
        }
        return result.detections;
      }

      if (result is _WorkerFailure) {
        final failureMessage = await _handleInferenceFailure(result.error);
        throw InferenceException(failureMessage);
      }

      return const [];
    } on TimeoutException {
      final failureMessage = await _handleInferenceFailure(
        'timeout after ${AppConstants.inferenceTimeoutMs}ms',
      );
      throw InferenceException(failureMessage);
    } catch (error, stackTrace) {
      if (error is InferenceException) rethrow;
      debugPrint('[DS] runInference error: $error\n$stackTrace');
      final failureMessage = await _handleInferenceFailure(error.toString());
      throw InferenceException(failureMessage);
    } finally {
      replyPort?.close();
      _isolateBusy = false;
    }
  }

  @override
  Future<void> closeModel() async {
    _modelLoaded = false;
    _allowAcceleration = true;
    _consecutiveFailures = 0;
    _lastInferenceMs = 0;
    await _shutdownIsolate();
  }
}

InterpreterRuntime? _runtime;
List<String> _runtimeLabels = const [];
int _runtimeInputSize = 0;
List<int> _runtimeOutputShape = const [];
Float32List? _cachedInputTensor;
int _runtimeInputTensorBytes = 0;
Uint8List? _cachedOutputBytes;
ByteBuffer? _cachedOutputBuffer;
Float32List? _cachedOutputFloats;
int _cachedOutputLength = 0;

void _isolateEntry(SendPort mainSendPort) {
  final jobPort = ReceivePort();
  mainSendPort.send(jobPort.sendPort);

  jobPort.listen((Object? message) async {
    if (message is _IsolateInitMessage) {
      await _handleInit(message);
      return;
    }

    if (message is _InferenceJob) {
      _handleInference(message);
      return;
    }

    if (message is _IsolateShutdown) {
      _closeRuntime();
      message.replyPort.send(true);
      jobPort.close();
      Isolate.exit();
    }
  });
}

Future<void> _handleInit(_IsolateInitMessage message) async {
  try {
    _closeRuntime();

    _runtimeLabels = message.labels;
    _runtimeInputSize = message.inputSize;

    final modelBytes = message.modelBytes.materialize().asUint8List();
    _runtime = _createInterpreterRuntime(
      modelBytes,
      allowAcceleration: message.allowAcceleration,
    );

    _runtimeInputTensorBytes = _validateInputShape(
      _runtime!.interpreter,
      _runtimeInputSize,
    );
    _runtimeOutputShape = _runtime!.interpreter.getOutputTensor(0).shape;
    _cachedInputTensor = null;
    _cachedOutputBytes = null;
    _cachedOutputBuffer = null;
    _cachedOutputFloats = null;
    _cachedOutputLength = 0;

    message.replyPort.send(
      _IsolateInitAck(
        outputShape: _runtimeOutputShape,
        delegateName: _runtime!.delegateName,
        isAccelerated: _runtime!.isAccelerated,
      ),
    );
  } catch (error, stackTrace) {
    debugPrint('[Isolate] init error: $error\n$stackTrace');
    _closeRuntime();
    message.replyPort.send(
      _IsolateInitAck(
        outputShape: const [],
        delegateName: 'failed',
        isAccelerated: false,
        error: error.toString(),
      ),
    );
  }
}

void _handleInference(_InferenceJob job) {
  final runtime = _runtime;
  if (runtime == null) {
    job.replyPort.send(const _WorkerFailure('interpreter not initialized'));
    return;
  }

  final totalStopwatch = Stopwatch()..start();

  try {
    final planes = <Uint8List>[
      for (final transferable in job.planeBytes)
        transferable.materialize().asUint8List(),
    ];

    // Reuse tensor memory structure continuously
    final letterbox = ImageConverter.yuvToLetterboxedFloat32(
      planes: planes,
      rowStrides: job.planeRowStrides,
      pixelStrides: job.planePixelStrides,
      srcWidth: job.imageWidth,
      srcHeight: job.imageHeight,
      inputSize: _runtimeInputSize,
      rotationDegrees: job.rotationDegrees,
      reuseBuffer: _cachedInputTensor,
    );
    _cachedInputTensor = letterbox.inputTensor;
    if (letterbox.inputBuffer.lengthInBytes != _runtimeInputTensorBytes) {
      throw StateError(
        'Input tensor byte size mismatch. expected=$_runtimeInputTensorBytes '
        'actual=${letterbox.inputBuffer.lengthInBytes}',
      );
    }

    _ensureOutputBuffer();

    // Use raw tensor bytes so tflite_flutter does not infer a rank-1 shape from
    // Float32List and resize the model input to `[N]` before allocation.
    runtime.interpreter.runForMultipleInputs(
      [letterbox.inputBuffer],
      <int, Object>{0: _cachedOutputBuffer!},
    );

    final detections = _parseDetections(
      flat: _cachedOutputFloats!,
      outputShape: _runtimeOutputShape,
      labels: _runtimeLabels,
      letterbox: letterbox,
      confidenceThreshold: job.confidenceThreshold,
      iouThreshold: job.iouThreshold,
      maxDetections: job.maxDetections,
    );

    totalStopwatch.stop();
    job.replyPort.send(
      _InferenceResult(
        detections: detections,
        totalLatencyMs: totalStopwatch.elapsedMilliseconds,
      ),
    );
  } catch (error, stackTrace) {
    debugPrint('[Isolate] inference error: $error\n$stackTrace');
    job.replyPort.send(_WorkerFailure(error.toString()));
  }
}

void _ensureOutputBuffer() {
  if (_runtimeOutputShape.length < 2) {
    throw StateError('Invalid output shape: $_runtimeOutputShape');
  }

  final length = _runtimeOutputShape.fold<int>(1, (acc, dim) => acc * dim);
  if (length <= 0) {
    throw StateError('Invalid output tensor length: $_runtimeOutputShape');
  }

  if (_cachedOutputLength == length && _cachedOutputBuffer != null) {
    return;
  }

  _cachedOutputBytes = Uint8List(length * Float32List.bytesPerElement);
  _cachedOutputBuffer = _cachedOutputBytes!.buffer;
  _cachedOutputFloats = _cachedOutputBuffer!.asFloat32List();
  _cachedOutputLength = length;
}

List<Map<String, dynamic>> _parseDetections({
  required Float32List flat,
  required List<int> outputShape,
  required List<String> labels,
  required LetterboxResult letterbox,
  required double confidenceThreshold,
  required double iouThreshold,
  required int maxDetections,
}) {
  // FIX: Passing missing 'flat' scope
  final layout = _resolveOutputLayout(flat, outputShape, labels.length);
  if (layout.availableClasses <= 0) return const [];

  final useSigmoid = _looksLikeLogits(layout);
  final coordinatesAreNormalized = AppConstants.yoloCoordinatesNormalized;
  final rawBoxes = <_RawDetection>[];

  for (int boxIndex = 0; boxIndex < layout.numBoxes; boxIndex++) {
    final cx = layout.at(boxIndex, 0);
    final cy = layout.at(boxIndex, 1);
    final bw = layout.at(boxIndex, 2);
    final bh = layout.at(boxIndex, 3);

    if (!cx.isFinite || !cy.isFinite || !bw.isFinite || !bh.isFinite) {
      continue;
    }
    if (bw <= 0 || bh <= 0) continue;

    final objectness = layout.hasObjectness
        ? _activate(layout.at(boxIndex, 4), useSigmoid)
        : 1.0;
    if (layout.hasObjectness && objectness <= 0) continue;

    final classCandidates = <_ClassCandidate>[];
    for (int classId = 0; classId < layout.availableClasses; classId++) {
      final classValue = layout.at(boxIndex, layout.classOffset + classId);
      final classScore = _activate(classValue, useSigmoid) * objectness;
      if (!classScore.isFinite || classScore < confidenceThreshold) continue;
      classCandidates.add(_ClassCandidate(classId, classScore));
    }

    if (classCandidates.isEmpty) continue;
    classCandidates.sort((a, b) => b.score.compareTo(a.score));

    final box = ImageConverter.unLetterboxBox(
      cx: cx,
      cy: cy,
      bw: bw,
      bh: bh,
      coordinatesAreNormalized: coordinatesAreNormalized,
      padLeft: letterbox.padLeft,
      padTop: letterbox.padTop,
      scale: letterbox.scale,
      origWidth: letterbox.origWidth,
      origHeight: letterbox.origHeight,
      inputSize: _runtimeInputSize,
    );

    if (!_isRenderableBox(box.width, box.height)) continue;

    final classLimit = min(
      AppConstants.maxClassesPerBox,
      classCandidates.length,
    );
    for (int i = 0; i < classLimit; i++) {
      final candidate = classCandidates[i];
      rawBoxes.add(
        _RawDetection(
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
          score: candidate.score,
          classId: candidate.classId,
        ),
      );
    }
  }

  if (rawBoxes.isEmpty) return const [];

  rawBoxes.sort((a, b) => b.score.compareTo(a.score));
  final selected = _nms(rawBoxes, iouThreshold).take(maxDetections);

  return selected
      .map(
        (box) => <String, dynamic>{
          'label': box.classId < labels.length
              ? labels[box.classId]
              : 'class_${box.classId}',
          'confidence': box.score,
          'left': box.left,
          'top': box.top,
          'width': box.width,
          'height': box.height,
        },
      )
      .toList(growable: false);
}

_OutputLayout _resolveOutputLayout(
  Float32List flat,
  List<int> shape,
  int labelCount,
) {
  if (shape.length < 2) {
    throw StateError('Unexpected output shape: $shape');
  }

  final dim0 = shape[shape.length - 2];
  final dim1 = shape.last;
  final channelsFirst = AppConstants.yoloChannelsFirst;
  final numBoxes = channelsFirst ? dim1 : dim0;
  final numChannels = channelsFirst ? dim0 : dim1;

  final hasObjectness = numChannels == labelCount + 5
      ? true
      : numChannels == labelCount + 4
          ? false
          : AppConstants.yoloHasObjectness;

  final classOffset = hasObjectness ? 5 : 4;
  final availableClasses = max(0, min(labelCount, numChannels - classOffset));

  double at(int boxIndex, int channelIndex) {
    if (channelsFirst) {
      return flat[channelIndex * numBoxes + boxIndex];
    }
    return flat[boxIndex * numChannels + channelIndex];
  }

  return _OutputLayout(
    numBoxes: numBoxes,
    numChannels: numChannels,
    classOffset: classOffset,
    availableClasses: availableClasses,
    hasObjectness: hasObjectness,
    at: at,
  );
}

bool _looksLikeLogits(_OutputLayout layout) {
  final step = max(1, layout.numBoxes ~/ 24);
  for (int boxIndex = 0; boxIndex < layout.numBoxes; boxIndex += step) {
    final limit = layout.classOffset + min(layout.availableClasses, 2);
    for (int channel = 4; channel < limit; channel++) {
      final value = layout.at(boxIndex, channel);
      if (!value.isFinite) continue;
      if (value < 0 || value > 1) return true;
    }
  }
  return AppConstants.yoloOutputLogits;
}

double _activate(double value, bool useSigmoid) {
  if (!useSigmoid) return value;
  return 1.0 / (1.0 + exp(-value));
}

bool _isRenderableBox(double width, double height) {
  if (width <= 0 || height <= 0) return false;

  final area = width * height;
  if (area < AppConstants.minRenderableBoxArea) return false;

  final aspectRatio = max(width / height, height / width);
  return aspectRatio <= AppConstants.maxRenderableAspectRatio;
}

List<_RawDetection> _nms(List<_RawDetection> boxes, double iouThreshold) {
  final selected = <_RawDetection>[];
  for (final box in boxes) {
    if (selected.every(
      (existing) =>
          existing.classId != box.classId ||
          _iou(existing, box) <= iouThreshold,
    )) {
      selected.add(box);
    }
  }
  return selected;
}

double _iou(_RawDetection a, _RawDetection b) {
  final left = max(a.left, b.left);
  final top = max(a.top, b.top);
  final right = min(a.left + a.width, b.left + b.width);
  final bottom = min(a.top + a.height, b.top + b.height);

  if (right <= left || bottom <= top) return 0;

  final intersection = (right - left) * (bottom - top);
  final union = a.width * a.height + b.width * b.height - intersection;
  if (union <= 0) return 0;
  return intersection / union;
}

int _validateInputShape(Interpreter interpreter, int expectedInputSize) {
  final inputTensor = interpreter.getInputTensor(0);
  final shape = inputTensor.shape;
  if (shape.length != 4) {
    throw StateError('Unexpected input rank ${shape.length}: $shape');
  }
  if (shape[0] != 1 || shape[3] != 3) {
    throw StateError('Unsupported input layout: $shape');
  }
  if (shape[1] != expectedInputSize || shape[2] != expectedInputSize) {
    throw StateError(
      'Model expects ${shape[1]}x${shape[2]}, app is configured for '
      '$expectedInputSize x $expectedInputSize',
    );
  }

  final expectedBytes =
      shape[0] * shape[1] * shape[2] * shape[3] * Float32List.bytesPerElement;
  if (inputTensor.numBytes() != expectedBytes) {
    throw StateError(
      'Unsupported input tensor storage: shape=$shape '
      'bytes=${inputTensor.numBytes()} expected=$expectedBytes',
    );
  }

  return expectedBytes;
}

InterpreterRuntime _createInterpreterRuntime(
  Uint8List modelBytes, {
  required bool allowAcceleration,
}) {
  if (Platform.isAndroid && allowAcceleration) {
    final gpuRuntime = _tryCreateGpuRuntime(modelBytes);
    if (gpuRuntime != null) return gpuRuntime;

    final nnapiRuntime = _tryCreateNnApiRuntime(modelBytes);
    if (nnapiRuntime != null) return nnapiRuntime;
  }

  if (Platform.isIOS && allowAcceleration) {
    final metalRuntime = _tryCreateMetalRuntime(modelBytes);
    if (metalRuntime != null) return metalRuntime;
  }

  final xnnpackRuntime = _tryCreateXnnpackRuntime(modelBytes);
  if (xnnpackRuntime != null) return xnnpackRuntime;

  final options = InterpreterOptions()..threads = AppConstants.inferenceThreads;
  final interpreter = Interpreter.fromBuffer(modelBytes, options: options);
  return InterpreterRuntime(
    interpreter: interpreter,
    delegateName: 'CPU',
    isAccelerated: false,
  );
}

InterpreterRuntime? _tryCreateGpuRuntime(Uint8List modelBytes) {
  GpuDelegateOptionsV2? delegateOptions;
  GpuDelegateV2? delegate;

  try {
    delegateOptions = GpuDelegateOptionsV2(isPrecisionLossAllowed: true);
    delegate = GpuDelegateV2(options: delegateOptions);
    final options = InterpreterOptions()..addDelegate(delegate);
    final interpreter = Interpreter.fromBuffer(modelBytes, options: options);

    return InterpreterRuntime(
      interpreter: interpreter,
      delegateName: 'GPU',
      isAccelerated: true,
      delegate: delegate,
      disposeExtras: delegateOptions.delete,
    );
  } catch (error) {
    debugPrint('[Isolate] GPU delegate unavailable: $error');
    try {
      delegate?.delete();
    } catch (_) {}
    try {
      delegateOptions?.delete();
    } catch (_) {}
    return null;
  }
}

InterpreterRuntime? _tryCreateNnApiRuntime(Uint8List modelBytes) {
  try {
    final options = InterpreterOptions()..useNnApiForAndroid = true;
    final interpreter = Interpreter.fromBuffer(modelBytes, options: options);
    return InterpreterRuntime(
      interpreter: interpreter,
      delegateName: 'NNAPI',
      isAccelerated: true,
    );
  } catch (error) {
    debugPrint('[Isolate] NNAPI unavailable: $error');
    return null;
  }
}

InterpreterRuntime? _tryCreateMetalRuntime(Uint8List modelBytes) {
  try {
    final options = InterpreterOptions()..useMetalDelegateForIOS = true;
    final interpreter = Interpreter.fromBuffer(modelBytes, options: options);
    return InterpreterRuntime(
      interpreter: interpreter,
      delegateName: 'Metal',
      isAccelerated: true,
    );
  } catch (error) {
    debugPrint('[Isolate] Metal delegate unavailable: $error');
    return null;
  }
}

InterpreterRuntime? _tryCreateXnnpackRuntime(Uint8List modelBytes) {
  XNNPackDelegateOptions? delegateOptions;
  XNNPackDelegate? delegate;

  try {
    delegateOptions =
        XNNPackDelegateOptions(numThreads: AppConstants.inferenceThreads);
    delegate = XNNPackDelegate(options: delegateOptions);
    final options = InterpreterOptions()..addDelegate(delegate);
    final interpreter = Interpreter.fromBuffer(modelBytes, options: options);

    return InterpreterRuntime(
      interpreter: interpreter,
      delegateName: 'XNNPack',
      isAccelerated: false,
      delegate: delegate,
      disposeExtras: delegateOptions.delete,
    );
  } catch (error) {
    debugPrint('[Isolate] XNNPack unavailable: $error');
    try {
      delegate?.delete();
    } catch (_) {}
    try {
      delegateOptions?.delete();
    } catch (_) {}
    return null;
  }
}

void _closeRuntime() {
  try {
    _runtime?.dispose();
  } catch (_) {}

  _runtime = null;
  _runtimeLabels = const [];
  _runtimeInputSize = 0;
  _runtimeOutputShape = const [];
  _cachedInputTensor = null;
  _runtimeInputTensorBytes = 0;
  _cachedOutputBytes = null;
  _cachedOutputBuffer = null;
  _cachedOutputFloats = null;
  _cachedOutputLength = 0;
}

class InterpreterRuntime {
  InterpreterRuntime({
    required this.interpreter,
    required this.delegateName,
    required this.isAccelerated,
    this.delegate,
    this.disposeExtras,
  });

  final Interpreter interpreter;
  final String delegateName;
  final bool isAccelerated;
  final Delegate? delegate;
  final void Function()? disposeExtras;

  void dispose() {
    try {
      interpreter.close();
    } finally {
      try {
        delegate?.delete();
      } finally {
        disposeExtras?.call();
      }
    }
  }
}

class _OutputLayout {
  const _OutputLayout({
    required this.numBoxes,
    required this.numChannels,
    required this.classOffset,
    required this.availableClasses,
    required this.hasObjectness,
    required this.at,
  });

  final int numBoxes;
  final int numChannels;
  final int classOffset;
  final int availableClasses;
  final bool hasObjectness;
  final double Function(int boxIndex, int channelIndex) at;
}

class _RawDetection {
  const _RawDetection({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.score,
    required this.classId,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final double score;
  final int classId;
}

class _ClassCandidate {
  const _ClassCandidate(this.classId, this.score);

  final int classId;
  final double score;
}

class _IsolateInitMessage {
  const _IsolateInitMessage({
    required this.labels,
    required this.inputSize,
    required this.modelBytes,
    required this.allowAcceleration,
    required this.replyPort,
  });

  final List<String> labels;
  final int inputSize;
  final TransferableTypedData modelBytes;
  final bool allowAcceleration;
  final SendPort replyPort;
}

class _IsolateInitAck {
  const _IsolateInitAck({
    required this.outputShape,
    required this.delegateName,
    required this.isAccelerated,
    this.error,
  });

  final List<int> outputShape;
  final String delegateName;
  final bool isAccelerated;
  final String? error;
}

class _InferenceJob {
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

  final SendPort replyPort;
  final List<TransferableTypedData> planeBytes;
  final List<int> planeRowStrides;
  final List<int> planePixelStrides;
  final int imageWidth;
  final int imageHeight;
  final int rotationDegrees;
  final double confidenceThreshold;
  final double iouThreshold;
  final int maxDetections;
}

class _InferenceResult {
  const _InferenceResult({
    required this.detections,
    required this.totalLatencyMs,
  });

  final List<Map<String, dynamic>> detections;
  final int totalLatencyMs;
}

class _WorkerFailure {
  const _WorkerFailure(this.error);

  final String error;
}

class _IsolateShutdown {
  const _IsolateShutdown({required this.replyPort});

  final SendPort replyPort;
}
