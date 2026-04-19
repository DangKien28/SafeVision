import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../error/exceptions.dart' as app_exceptions;
import '../models/camera_frame.dart';

// Re-export so that existing `import '...camera_service.dart' show CameraFrame`
// calls resolve to the same type as the domain layer's import of
// `core/models/camera_frame.dart`.  Previously camera_service.dart defined its
// own CameraFrame class, which created a distinct type from the model's class
// and caused argument_type_not_assignable / invalid_override errors everywhere
// the two were used together (datasource, repository, use-case, tests).
export '../models/camera_frame.dart' show CameraFrame;

/// Manages the device camera lifecycle and delivers frames to callers.
class CameraService {
  CameraService();

  CameraController? _controller;
  bool _isProcessingFrame = false;
  Future<void>? _disposeFuture;
  bool _isFrontCamera = false;
  int _rotationDegrees = 90;

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isFrontCamera => _isFrontCamera;
  int get rotationDegrees => _rotationDegrees;
  CameraController? get controller => _controller;

  /// Initializes the camera controller.
  ///
  /// If a previous [dispose] call is still in progress, this waits for that
  /// teardown to complete before acquiring a new camera handle.
  Future<void> initialize() async {
    await disposeFuture;

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw app_exceptions.CameraException('No cameras available on device');
    }

    final description = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _isFrontCamera = description.lensDirection == CameraLensDirection.front;
    _rotationDegrees = _isFrontCamera ? 270 : 90;

    // BUG FIX 1: was ResolutionPreset.low (240 × 320). Medium gives ≈ 480p.
    _controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
    } on CameraException catch (e) {
      throw app_exceptions.CameraException(
        'Failed to initialize camera: ${e.description}',
      );
    }
  }

  /// Switches to the other lens direction (back ↔ front) and reinitialises
  /// the controller.  The caller must stop the image stream before calling
  /// this and restart it afterwards.
  ///
  /// If a previous [dispose] call is still in progress, this waits for that
  /// teardown to complete before switching.
  Future<void> switchCamera() async {
    await disposeFuture;

    _isFrontCamera = !_isFrontCamera;
    _rotationDegrees = _isFrontCamera ? 270 : 90;

    final cameras = await availableCameras();
    final targetDirection =
        _isFrontCamera ? CameraLensDirection.front : CameraLensDirection.back;

    final description = cameras.firstWhere(
      (c) => c.lensDirection == targetDirection,
      orElse: () => cameras.first,
    );

    await dispose();

    _controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
    } on CameraException catch (e) {
      throw app_exceptions.CameraException(
        'Failed to switch camera: ${e.description}',
      );
    }
  }

  /// Starts the YUV420 image stream at [AppConstants.activeInferenceFps].
  ///
  /// [onFrame] receives an immutable [CameraFrame] and an [onDone] callback
  /// that MUST be called exactly once (in a finally block) to release the
  /// frame lock and allow the next frame to be delivered.
  Future<void> startImageStream({
    required void Function(CameraFrame frame, VoidCallback onDone) onFrame,
  }) async {
    _assertInitialized();

    final interval = Duration(
      milliseconds: (1000 / AppConstants.activeInferenceFps).round(),
    );
    DateTime lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);

    await _controller!.startImageStream((CameraImage image) {
      final now = DateTime.now();
      if (now.difference(lastFrameTime) < interval) return;
      if (_isProcessingFrame) return;

      _isProcessingFrame = true;
      lastFrameTime = now;

      final frame = CameraFrame(
        planes: image.planes.map((p) => p.bytes).toList(),
        rowStrides: image.planes.map((p) => p.bytesPerRow).toList(),
        pixelStrides: image.planes.map((p) => p.bytesPerPixel ?? 1).toList(),
        width: image.width,
        height: image.height,
      );

      onFrame(frame, _releaseFrameLock);
    });
  }

  Future<void> stopImageStream() async {
    if (_controller?.value.isStreamingImages ?? false) {
      await _controller!.stopImageStream();
    }
    _isProcessingFrame = false;
  }

  /// Disposes the active camera controller and returns a future that completes
  /// when native camera teardown finishes.
  ///
  /// Safe to call multiple times; concurrent calls share the same in-flight
  /// future until disposal completes.
  Future<void> dispose() {
    _isProcessingFrame = false;

    if (_disposeFuture != null) {
      return _disposeFuture!;
    }

    final controller = _controller;
    _controller = null;

    if (controller == null) {
      return Future.value();
    }

    final cleanupFuture = controller.dispose().whenComplete(() {
      _disposeFuture = null;
    });
    _disposeFuture = cleanupFuture;
    return cleanupFuture;
  }

  Future<void> get disposeFuture => _disposeFuture ?? Future.value();

  void _releaseFrameLock() => _isProcessingFrame = false;

  void _assertInitialized() {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw app_exceptions.CameraException(
        'CameraService.initialize() must be called before streaming',
      );
    }
  }
}
