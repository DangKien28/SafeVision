import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:safe_vision_app/core/utils/perf_monitor.dart';
import '../constants/app_constants.dart';
import '../error/exceptions.dart' as ex;

/// Manages the [CameraController] lifecycle and the YUV420 frame stream.
///
/// Main responsibilities:
/// - Initialize and dispose the controller safely.
/// - Throttle frame rate using [AppConstants.activeInferenceFps].
/// - Guard concurrent frame processing through [_isProcessingFrame].
/// - Invalidate stale stream callbacks with [_streamGeneration] when the
///   camera is switched or reinitialized.
///
/// Frame locking is owned entirely by [CameraService]. The [onFrame] callback
/// receives an [onDone] function that must be called after inference finishes.
/// If [onDone] is missed, the stream stays locked and freezes.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentIndex = 0;
  int _rotationDegrees = 0;
  int _busyDropCount = 0;
  int _throttleDropCount = 0;

  DateTime _lastFrameTime = DateTime.now();

  /// Minimum interval between frames in milliseconds for the target FPS.
  static const int _minFrameMs = 1000 ~/ AppConstants.activeInferenceFps;

  /// Frame processing lock.
  ///
  /// THREADING INVARIANT: This field is read and written exclusively on the
  /// main Dart isolate. Flutter's camera plugin delivers image-stream
  /// callbacks on the platform thread, which is then scheduled into the
  /// main Dart event loop — making mutation here safe without a mutex.
  ///
  /// If the camera plugin changes this delivery guarantee in a future
  /// version, this field must be replaced with an atomic or a
  /// [Completer]-based lock.
  bool _isProcessingFrame = false;

  bool _isInitializing = false;
  bool _isDisposing = false;
  Future<void>? _disposeFuture;

  /// Incremented every time the camera is initialized or switched.
  /// Each frame callback captures the current generation and is ignored if it
  /// no longer matches the latest value.
  int _streamGeneration = 0;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming => _controller?.value.isStreamingImages ?? false;
  bool get isFrontCamera =>
      _cameras.isNotEmpty &&
      _cameras[_currentIndex].lensDirection == CameraLensDirection.front;
  int get sensorOrientation =>
      _cameras.isNotEmpty ? _cameras[_currentIndex].sensorOrientation : 0;
  int get rotationDegrees => _rotationDegrees;

  // Initialization

  Future<void> initialize({int cameraIndex = 0}) async {
    // Wait for any previous dispose operation to finish before reinitializing.
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
        throw const ex.CameraException('Không tìm thấy camera');
      }
      _currentIndex = cameraIndex.clamp(0, _cameras.length - 1);
      await _setupController(_cameras[_currentIndex]);
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    final old = _controller;
    _streamGeneration++;
    _isProcessingFrame = false;
    _controller = null;

    // Dispose the old controller before creating a new one.
    if (old != null) {
      try {
        if (old.value.isStreamingImages) await old.stopImageStream();
        await old.dispose();
      } catch (e) {
        debugPrint('[CameraService] dispose old controller error: $e');
      }
    }

    // Front-camera rotation is mirrored because the sensor is mounted in the
    // opposite direction.
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
      '[CameraService] camera ready: ${camera.name} (${camera.lensDirection}) '
      'sensor=${camera.sensorOrientation} rotation=$_rotationDegrees',
    );
  }

  // Stream

  /// Starts the camera frame stream.
  ///
  /// [onFrame] is called for frames that pass throttling and the busy guard.
  /// The second parameter, [onDone], must be called after inference completes
  /// so the next frame can proceed.
  void startImageStream({
    required void Function(CameraImage, void Function()) onFrame,
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
    _busyDropCount = 0;
    _throttleDropCount = 0;

    final int streamGeneration = ++_streamGeneration;

    unawaited(controller.startImageStream((CameraImage image) {
      // Ignore frames from a stream generation that is no longer valid.
      if (_isDisposing ||
          _controller != controller ||
          _streamGeneration != streamGeneration) {
        return;
      }

      // Drop the frame if the previous inference is still running.
      if (_isProcessingFrame) {
        PerfMonitor.frameDropped();
        _busyDropCount++;
        if (kDebugMode && _busyDropCount % 30 == 0) {
          debugPrint(
              '[CameraService] dropped $_busyDropCount frames: inference busy');
        }
        return;
      }

      // Drop the frame if the minimum frame interval has not been reached yet.
      final now = DateTime.now();
      if (now.difference(_lastFrameTime).inMilliseconds < _minFrameMs) {
        _throttleDropCount++;
        if (kDebugMode && _throttleDropCount % 30 == 0) {
          debugPrint(
              '[CameraService] dropped $_throttleDropCount frames: fps throttle');
        }
        return;
      }

      _isProcessingFrame = true;
      _lastFrameTime = now;

      onFrame(image, () {
        // onDone releases the processing lock and should be called by the
        // caller after inference finishes, including from a finally block.
        _isProcessingFrame = false;
      });
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint('[CameraService] startImageStream error: $error');
    }));

    debugPrint(
        '[CameraService] stream started (~${AppConstants.activeInferenceFps}fps)');
  }

  Future<void> stopImageStream() async {
    _streamGeneration++;
    _isProcessingFrame = false;
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
    _currentIndex = (_currentIndex + 1) % _cameras.length;
    await _setupController(_cameras[_currentIndex]);
  }

  // Dispose

  /// Disposes the controller and clears all resources.
  /// The method is idempotent: repeated calls wait for the first one to finish.
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
