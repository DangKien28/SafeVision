// lib/core/services/camera_service.dart
//
// v4: Introduces CameraFrame — copies plane bytes on arrival, releases
// Android AHardwareBuffer before inference begins.
//
// ROOT CAUSE of BLASTBufferQueue / MALI DEBUG errors:
//   CameraImage holds a reference to the Android camera HAL buffer
//   (AHardwareBuffer slot). Keeping CameraImage alive for the full inference
//   duration (~2640ms CPU) prevented the camera HAL from recycling that slot.
//   With 7 total buffer slots (max:5+2) and inference occupying one for 2640ms
//   at ~30fps camera output, the producer filled all slots and BLASTBufferQueue
//   logged: "Can't acquire next buffer. Already acquired max frames 7".
//
// Fix: copy all plane bytes into Uint8List inside the camera callback before
// dispatching. CameraImage is then immediately eligible for GC and buffer
// recycling, independent of inference duration.

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
  /// After this constructor returns, no reference to [image.planes] is
  /// retained, allowing the Android buffer slot to be returned to the pool.
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

/// Manages the [CameraController] lifecycle and the YUV420 frame stream.
///
/// Main responsibilities:
/// - Initialize and dispose the controller safely.
/// - Throttle frame rate using [AppConstants.activeInferenceFps].
/// - Guard concurrent frame processing through [_isProcessingFrame].
/// - Invalidate stale stream callbacks with [_streamGeneration] when the
///   camera is switched or reinitialized.
///
/// v4: [startImageStream] callback receives [CameraFrame] instead of
/// [CameraImage]. Plane bytes are copied inside the stream callback so the
/// Android camera HAL buffer is released before inference begins.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentIndex = 0;
  int _rotationDegrees = 0;
  int _busyDropCount = 0;
  int _throttleDropCount = 0;

  DateTime _lastFrameTime = DateTime.now();

  static const int _minFrameMs = 1000 ~/ AppConstants.activeInferenceFps;

  /// Frame processing lock.
  /// THREADING INVARIANT: read/written exclusively on the main Dart isolate.
  bool _isProcessingFrame = false;

  bool _isInitializing = false;
  bool _isDisposing = false;
  Future<void>? _disposeFuture;

  /// Incremented whenever the camera is initialized or switched.
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
      '[CameraService] camera ready: ${camera.name} (${camera.lensDirection}) '
      'sensor=${camera.sensorOrientation} rotation=$_rotationDegrees',
    );
  }

  /// Starts the camera frame stream.
  ///
  /// [onFrame] receives a [CameraFrame] (plane bytes already copied) and an
  /// [onDone] callback that MUST be called after inference completes to
  /// release the processing lock for the next frame.
  ///
  /// v4: Plane bytes are copied inside the stream callback via
  /// [CameraFrame.fromCameraImage] before [onFrame] is invoked, so the
  /// Android camera HAL buffer is recycled before inference begins.
  void startImageStream({
    required void Function(CameraFrame, void Function()) onFrame,
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
      if (_isDisposing ||
          _controller != controller ||
          _streamGeneration != streamGeneration) {
        return;
      }

      if (_isProcessingFrame) {
        PerfMonitor.frameDropped();
        _busyDropCount++;
        if (kDebugMode && _busyDropCount % 30 == 0) {
          debugPrint(
              '[CameraService] dropped $_busyDropCount frames: inference busy');
        }
        return;
      }

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

      // v4: Copy plane bytes immediately. After this line, `image` is not
      // referenced by this closure. The camera plugin's buffer finalizer
      // can reclaim the AHardwareBuffer slot independently of inference.
      final CameraFrame frame = CameraFrame.fromCameraImage(image);

      onFrame(frame, () {
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
