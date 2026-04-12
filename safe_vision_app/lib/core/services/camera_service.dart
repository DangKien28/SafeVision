import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:safe_vision_app/core/utils/perf_monitor.dart';
import '../constants/app_constants.dart';
import '../error/exceptions.dart' as ex;

/// Immutable snapshot of one camera frame with plane bytes already copied.
///
/// Unlike [CameraImage], this holds no reference to the underlying Android
/// AHardwareBuffer. The camera HAL can recycle its buffer slot as soon as
/// the [CameraImage] that produced this frame is garbage-collected — which
/// happens immediately after [CameraFrame.fromCameraImage] returns.
class CameraFrame {
  final List<Uint8List> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;
  final int width;
  final int height;

  const CameraFrame({
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
    required this.width,
    required this.height,
  });

  /// Copies all plane bytes from [image] into heap-allocated [Uint8List]s.
  /// After this returns, no reference to [image.planes] is retained, allowing
  /// the Android AHardwareBuffer slot to return to the HAL pool immediately.
  factory CameraFrame.fromCameraImage(CameraImage image) {
    return CameraFrame(
      planes: image.planes
          .map((p) => Uint8List.fromList(p.bytes))
          .toList(growable: false),
      rowStrides:
          image.planes.map((p) => p.bytesPerRow).toList(growable: false),
      pixelStrides:
          image.planes.map((p) => p.bytesPerPixel ?? 1).toList(growable: false),
      width: image.width,
      height: image.height,
    );
  }
}

/// Manages the [CameraController] lifecycle and the YUV420 frame stream
/// with a latest-frame buffering strategy.
///
/// LATEST-FRAME STRATEGY:
/// When inference is busy, incoming frames are stored in [_pendingFrame]
/// (overwriting on each new arrival) rather than being dropped. After
/// inference completes, [_handleInferenceDone] immediately dispatches
/// the buffered frame via [Future.microtask], ensuring detections always
/// reflect the most recent camera state.
///
/// THREADING INVARIANT: all mutable state read/written exclusively on the
/// main Dart isolate (Dart is single-threaded on main). No synchronisation
/// primitives are required.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentIndex = 0;
  int _rotationDegrees = 0;

  // Telemetry counters (debug only)
  int _bufferedCount = 0; // Frames stored as pending (not truly dropped)
  int _throttleCount = 0; // Frames below FPS minimum interval

  DateTime _lastFrameTime = DateTime.now();
  static const int _minFrameMs = 1000 ~/ AppConstants.activeInferenceFps;

  // Single-flight inference guard. True while the downstream handler has not
  // yet called onDone(). Only one frame may be in-flight at any time.
  bool _isProcessingFrame = false;

  bool _isInitializing = false;
  bool _isDisposing = false;
  Future<void>? _disposeFuture;

  /// Incremented on every initialize / switchCamera / stopImageStream call.
  /// Stale callbacks capture the old generation and are discarded.
  int _streamGeneration = 0;

  // ── Latest-frame buffer ───────────────────────────────────────────────────

  /// The most recently captured frame while inference was busy.
  /// Overwritten by each new arrival; null when no pending frame exists.
  CameraFrame? _pendingFrame;

  /// Wall-clock time when [_pendingFrame] was captured.
  DateTime? _pendingFrameTime;

  /// The active inference callback. Stored as a member so _handleInferenceDone
  /// can reference it without a stale closure.
  void Function(CameraFrame frame, void Function() onDone)? _onFrameCallback;

  // ── Public getters ────────────────────────────────────────────────────────

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming => _controller?.value.isStreamingImages ?? false;
  bool get isFrontCamera =>
      _cameras.isNotEmpty &&
      _cameras[_currentIndex].lensDirection == CameraLensDirection.front;
  int get sensorOrientation =>
      _cameras.isNotEmpty ? _cameras[_currentIndex].sensorOrientation : 0;
  int get rotationDegrees => _rotationDegrees;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize({int cameraIndex = 0}) async {
    final pendingDispose = _disposeFuture;
    if (pendingDispose != null) await pendingDispose;

    if (_isInitializing) {
      debugPrint('[CameraService] initialize: already in progress, skip');
      return;
    }
    _isInitializing = true;
    try {
      _isDisposing = false;
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw const ex.CameraException('No camera found');
      }
      _currentIndex = cameraIndex.clamp(0, _cameras.length - 1);
      await _setupController(_cameras[_currentIndex]);
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    final old = _controller;

    // Advance generation: stale callbacks from the previous stream will
    // detect the mismatch and return without dispatching.
    _streamGeneration++;
    _isProcessingFrame = false;
    _pendingFrame = null;
    _pendingFrameTime = null;
    _onFrameCallback = null;
    _controller = null;

    if (old != null) {
      try {
        if (old.value.isStreamingImages) await old.stopImageStream();
        await old.dispose();
      } catch (e) {
        debugPrint('[CameraService] dispose old controller error: $e');
      }
    }

    final bool isFront = camera.lensDirection == CameraLensDirection.front;
    _rotationDegrees = isFront
        ? camera.sensorOrientation % 360
        : (360 - camera.sensorOrientation) % 360;

    final ctrl = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await ctrl.initialize();
    _controller = ctrl;

    debugPrint(
      '[CameraService] camera ready: ${camera.name} '
      '(${camera.lensDirection}) '
      'sensor=${camera.sensorOrientation} '
      'rotation=$_rotationDegrees',
    );
  }

  // ── Stream management ─────────────────────────────────────────────────────

  /// Starts the camera frame stream with latest-frame buffering.
  ///
  /// [onFrame] receives a [CameraFrame] (plane bytes already copied) and an
  /// [onDone] callback that MUST be called after inference completes to
  /// release the single-flight lock and trigger dispatch of any pending frame.
  ///
  /// LATEST-FRAME STRATEGY:
  /// - Frames arriving while inference is busy are stored in [_pendingFrame],
  ///   overwriting the previous pending frame.
  /// - When [onDone] is called, [_handleInferenceDone] dispatches the buffered
  ///   frame via [Future.microtask] so [droppable()] sees the current BLoC
  ///   event as settled before the new event is added.
  void startImageStream({
    required void Function(CameraFrame frame, void Function() onDone) onFrame,
  }) {
    if (_controller == null || !isInitialized || _isDisposing) {
      debugPrint('[CameraService] startImageStream: not ready, skip');
      return;
    }
    final controller = _controller!;
    if (controller.value.isStreamingImages) {
      debugPrint('[CameraService] already streaming');
      return;
    }

    _lastFrameTime = DateTime.now();
    _isProcessingFrame = false;
    _pendingFrame = null;
    _pendingFrameTime = null;
    _bufferedCount = 0;
    _throttleCount = 0;
    _onFrameCallback = onFrame;

    final int gen = ++_streamGeneration;

    unawaited(controller.startImageStream((CameraImage image) {
      // ── Stale-stream guard ───────────────────────────────────────────────
      if (_isDisposing ||
          _controller != controller ||
          _streamGeneration != gen) {
        return;
      }

      // ── FPS throttle ─────────────────────────────────────────────────────
      // Limits HAL callbacks to activeInferenceFps to reduce CPU overhead
      // from frame copying while still providing fresh pending frames.
      final now = DateTime.now();
      if (now.difference(_lastFrameTime).inMilliseconds < _minFrameMs) {
        _throttleCount++;
        if (kDebugMode && _throttleCount % 120 == 0) {
          debugPrint('[CameraService] throttled $_throttleCount frames');
        }
        return;
      }
      _lastFrameTime = now;

      // ── v5: Copy bytes immediately to release AHardwareBuffer ─────────────
      // After this line, CameraImage is not referenced. The HAL buffer slot
      // returns to the pool, preventing BLASTBufferQueue exhaustion.
      final CameraFrame frame = CameraFrame.fromCameraImage(image);

      PerfMonitor.frameReceived();

      if (_isProcessingFrame) {
        // ── LATEST-FRAME STRATEGY ─────────────────────────────────────────
        // Overwrite pending with the newest frame. The previous pending frame
        // (if any) becomes eligible for GC immediately.
        _pendingFrame = frame;
        _pendingFrameTime = now;
        _bufferedCount++;
        if (kDebugMode && _bufferedCount % 30 == 0) {
          debugPrint(
              '[CameraService] latest-frame buffer: $_bufferedCount frames '
              'buffered (inference busy)');
        }
        return;
      }

      _sendFrame(frame, gen);
    }).catchError((Object error, StackTrace _) {
      debugPrint('[CameraService] startImageStream error: $error');
    }));

    debugPrint('[CameraService] stream started with latest-frame strategy '
        '(~${AppConstants.activeInferenceFps}fps capture)');
  }

  /// Dispatches [frame] for inference. Must only be called when
  /// [_isProcessingFrame] is false.
  void _sendFrame(CameraFrame frame, int gen) {
    assert(
      !_isProcessingFrame,
      '[CameraService] _sendFrame called while already processing',
    );

    _isProcessingFrame = true;
    _pendingFrame = null;
    _pendingFrameTime = null;

    _onFrameCallback?.call(frame, () => _handleInferenceDone(gen));
  }

  /// Called by the DetectionBloc (via onDone) after inference completes.
  ///
  /// Uses [Future.microtask] to schedule the next frame dispatch AFTER the
  /// current BLoC event handler fully settles. Without the microtask, calling
  /// [DetectionBloc.add()] from within the [finally] block of [_onFrameReceived]
  /// causes [droppable()] to see the handler as still active and silently
  /// drop the new event — breaking the pipeline entirely (RC-3).
  void _handleInferenceDone(int gen) {
    _isProcessingFrame = false;

    // Guard: stream was reset or service disposed while inference was running.
    if (_isDisposing || _streamGeneration != gen || _onFrameCallback == null) {
      _pendingFrame = null;
      _pendingFrameTime = null;
      return;
    }

    final pending = _pendingFrame;
    final pendingTime = _pendingFrameTime;
    if (pending == null || pendingTime == null) return;

    // ── Stale-frame guard ────────────────────────────────────────────────────
    // If the pending frame is older than latestFrameMaxAgeMs, it would produce
    // a detection for a scene that no longer exists. Discard it and wait for
    // the next live frame from the camera stream.
    final ageMs = DateTime.now().difference(pendingTime).inMilliseconds;
    if (ageMs > AppConstants.latestFrameMaxAgeMs) {
      if (kDebugMode) {
        debugPrint('[CameraService] pending frame discarded: ${ageMs}ms old '
            '(> ${AppConstants.latestFrameMaxAgeMs}ms limit)');
      }
      _pendingFrame = null;
      _pendingFrameTime = null;
      return;
    }

    // ── FIX RC-3: microtask delay ─────────────────────────────────────────
    // Capture local references before the microtask runs — member variables
    // may change between scheduling and execution.
    final capturedPending = pending;
    final capturedGen = gen;

    Future.microtask(() {
      // Re-check all guards inside the microtask: state may have changed
      // between scheduling and execution (camera switch, dispose, etc.).
      if (_isDisposing ||
          _streamGeneration != capturedGen ||
          _onFrameCallback == null ||
          _isProcessingFrame) {
        // Another live frame arrived first (_isProcessingFrame == true) or
        // the stream was reset. Either way, the capturedPending frame is
        // now stale — let it be GC'd.
        return;
      }

      _sendFrame(capturedPending, capturedGen);
    });
  }

  Future<void> stopImageStream() async {
    _streamGeneration++;
    _isProcessingFrame = false;
    _pendingFrame = null;
    _pendingFrameTime = null;
    _onFrameCallback = null;

    final controller = _controller;
    try {
      if (controller?.value.isStreamingImages ?? false) {
        await controller!.stopImageStream();
        debugPrint('[CameraService] stream stopped');
      }
    } catch (e) {
      debugPrint('[CameraService] stopImageStream error: $e');
    }
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;
    _pendingFrame = null;
    _pendingFrameTime = null;
    _onFrameCallback = null;
    _currentIndex = (_currentIndex + 1) % _cameras.length;
    await _setupController(_cameras[_currentIndex]);
  }

  Future<void> dispose() async {
    final pendingDispose = _disposeFuture;
    if (pendingDispose != null) {
      await pendingDispose;
      return;
    }

    final controller = _controller;
    _controller = null;
    _isDisposing = true;
    _streamGeneration++;
    _isProcessingFrame = false;
    _pendingFrame = null;
    _pendingFrameTime = null;
    _onFrameCallback = null;

    final completer = Completer<void>();
    _disposeFuture = completer.future;
    try {
      try {
        if (controller?.value.isStreamingImages ?? false) {
          await controller!.stopImageStream();
        }
      } catch (e) {
        debugPrint('[CameraService] dispose stop stream error: $e');
      }
      try {
        await controller?.dispose();
      } catch (e) {
        debugPrint('[CameraService] dispose controller error: $e');
      }
    } finally {
      _isProcessingFrame = false;
      _isDisposing = false;
      _disposeFuture = null;
      completer.complete();
    }
  }
}
