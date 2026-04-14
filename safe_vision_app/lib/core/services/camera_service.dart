import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/camera_frame.dart';
import '../constants/app_constants.dart';
import '../error/exceptions.dart' as ex;
import '../utils/perf_monitor.dart';
export '../models/camera_frame.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _currentIndex = 0;
  int _baseRotationDegrees = 0;

  int _latestRefreshCount = 0;
  int _throttleCount = 0;

  DateTime _lastFrameTime = DateTime.now();
  DateTime? _pendingFrameTime;
  DateTime? _pendingFrameUpdatedAt;

  CameraFrame? _pendingFrame;
  bool _isProcessingFrame = false;
  bool _isInitializing = false;
  bool _isDisposing = false;
  Future<void>? _disposeFuture;
  int _streamGeneration = 0;

  void Function(CameraFrame frame, void Function() onDone)? _onFrameCallback;

  static const int _minFrameMs = 1000 ~/ AppConstants.activeInferenceFps;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming => _controller?.value.isStreamingImages ?? false;
  bool get isFrontCamera =>
      _cameras.isNotEmpty &&
      _cameras[_currentIndex].lensDirection == CameraLensDirection.front;
  int get sensorOrientation =>
      _cameras.isNotEmpty ? _cameras[_currentIndex].sensorOrientation : 0;
  int get rotationDegrees => _computeRotationDegrees();

  Future<void> initialize({int cameraIndex = 0}) async {
    final pendingDispose = _disposeFuture;
    if (pendingDispose != null) await pendingDispose;

    if (_isInitializing) {
      debugPrint('[CameraService] initialize: already in progress');
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
    final oldController = _controller;

    _streamGeneration++;
    _resetStreamState();
    _controller = null;

    if (oldController != null) {
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
      } catch (error) {
        debugPrint('[CameraService] stop old stream error: $error');
      }
      try {
        await oldController.dispose();
      } catch (error) {
        debugPrint('[CameraService] dispose old controller error: $error');
      }
    }

    final isFront = camera.lensDirection == CameraLensDirection.front;
    _baseRotationDegrees = isFront
        ? camera.sensorOrientation % 360
        : (360 - camera.sensorOrientation) % 360;

    final controller = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    _controller = controller;

    debugPrint(
      '[CameraService] ready: ${camera.name} '
      '(${camera.lensDirection}) '
      'sensor=${camera.sensorOrientation} '
      'rotation=$rotationDegrees',
    );
  }

  int _computeRotationDegrees() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _baseRotationDegrees;
    }

    final orientation = controller.value.lockedCaptureOrientation ??
        controller.value.deviceOrientation;
    return (_baseRotationDegrees + _deviceOrientationDegrees(orientation)) %
        360;
  }

  int _deviceOrientationDegrees(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return 0;
      case DeviceOrientation.landscapeRight:
        return 90;
      case DeviceOrientation.portraitDown:
        return 180;
      case DeviceOrientation.landscapeLeft:
        return 270;
    }
  }

  void startImageStream({
    required void Function(CameraFrame frame, void Function() onDone) onFrame,
  }) {
    if (_controller == null || !isInitialized || _isDisposing) {
      debugPrint('[CameraService] startImageStream: not ready');
      return;
    }

    final controller = _controller!;
    if (controller.value.isStreamingImages) {
      debugPrint('[CameraService] startImageStream: already streaming');
      return;
    }

    _lastFrameTime = DateTime.now();
    _latestRefreshCount = 0;
    _throttleCount = 0;
    _resetStreamState();
    _onFrameCallback = onFrame;
    PerfMonitor.reset();

    final generation = ++_streamGeneration;

    unawaited(controller.startImageStream((CameraImage image) {
      if (_isDisposing ||
          _controller != controller ||
          _streamGeneration != generation) {
        return;
      }

      final now = DateTime.now();
      if (now.difference(_lastFrameTime).inMilliseconds < _minFrameMs) {
        _throttleCount++;
        PerfMonitor.frameDropped();
        if (kDebugMode && _throttleCount % 120 == 0) {
          debugPrint('[CameraService] throttled $_throttleCount frames');
        }
        return;
      }
      _lastFrameTime = now;

      if (_isProcessingFrame) {
        final shouldRefreshPending = _pendingFrame == null ||
            _pendingFrameUpdatedAt == null ||
            now.difference(_pendingFrameUpdatedAt!).inMilliseconds >=
                AppConstants.busyFrameReplacementMinIntervalMs;
        if (!shouldRefreshPending) {
          PerfMonitor.frameDropped();
          return;
        }

        _pendingFrame = image.toCameraFrame();
        _pendingFrameTime = now;
        _pendingFrameUpdatedAt = now;
        _latestRefreshCount++;
        PerfMonitor.latestFrameQueued();

        if (kDebugMode && _latestRefreshCount % 30 == 0) {
          debugPrint('[CameraService] refreshed latest pending frame '
              '$_latestRefreshCount times');
        }
        return;
      }

      _dispatchFrame(image.toCameraFrame(), generation);
    }).catchError((Object error, StackTrace _) {
      debugPrint('[CameraService] startImageStream error: $error');
    }));

    debugPrint(
      '[CameraService] stream started (~${AppConstants.activeInferenceFps} fps)',
    );
  }

  void _dispatchFrame(CameraFrame frame, int generation) {
    assert(!_isProcessingFrame);

    _isProcessingFrame = true;
    _pendingFrame = null;
    _pendingFrameTime = null;
    _pendingFrameUpdatedAt = null;
    PerfMonitor.frameDispatched();

    final onFrame = _onFrameCallback;
    if (onFrame == null) {
      _handleInferenceDone(generation);
      return;
    }

    try {
      onFrame(frame, () => _handleInferenceDone(generation));
    } catch (error, stackTrace) {
      debugPrint('[CameraService] frame callback error: $error\n$stackTrace');
      _handleInferenceDone(generation);
    }
  }

  void _handleInferenceDone(int generation) {
    _isProcessingFrame = false;

    if (_isDisposing ||
        _streamGeneration != generation ||
        _onFrameCallback == null) {
      _pendingFrame = null;
      _pendingFrameTime = null;
      _pendingFrameUpdatedAt = null;
      return;
    }

    final pendingFrame = _pendingFrame;
    final pendingFrameTime = _pendingFrameTime;
    if (pendingFrame == null || pendingFrameTime == null) {
      return;
    }

    final ageMs = DateTime.now().difference(pendingFrameTime).inMilliseconds;
    if (ageMs > AppConstants.latestFrameMaxAgeMs) {
      if (kDebugMode) {
        debugPrint('[CameraService] stale pending frame dropped: ${ageMs}ms');
      }
      _pendingFrame = null;
      _pendingFrameTime = null;
      _pendingFrameUpdatedAt = null;
      PerfMonitor.frameDropped();
      return;
    }

    Future.microtask(() {
      if (_isDisposing ||
          _streamGeneration != generation ||
          _onFrameCallback == null ||
          _isProcessingFrame) {
        return;
      }
      _dispatchFrame(pendingFrame, generation);
    });
  }

  Future<void> stopImageStream() async {
    _streamGeneration++;
    _resetStreamState();

    final controller = _controller;
    try {
      if (controller?.value.isStreamingImages ?? false) {
        await controller!.stopImageStream();
        debugPrint('[CameraService] stream stopped');
      }
    } catch (error) {
      debugPrint('[CameraService] stopImageStream error: $error');
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
    _resetStreamState();

    final completer = Completer<void>();
    _disposeFuture = completer.future;
    try {
      try {
        if (controller?.value.isStreamingImages ?? false) {
          await controller!.stopImageStream();
        }
      } catch (error) {
        debugPrint('[CameraService] dispose stop stream error: $error');
      }
      try {
        await controller?.dispose();
      } catch (error) {
        debugPrint('[CameraService] dispose controller error: $error');
      }
    } finally {
      _isDisposing = false;
      _disposeFuture = null;
      completer.complete();
    }
  }

  void _resetStreamState() {
    _isProcessingFrame = false;
    _pendingFrame = null;
    _pendingFrameTime = null;
    _pendingFrameUpdatedAt = null;
    _onFrameCallback = null;
  }
}

extension CameraImageFrameMapper on CameraImage {
  CameraFrame toCameraFrame() {
    return CameraFrame(
      planes: planes
          .map((plane) => Uint8List.fromList(plane.bytes))
          .toList(growable: false),
      rowStrides:
          planes.map((plane) => plane.bytesPerRow).toList(growable: false),
      pixelStrides: planes
          .map((plane) => plane.bytesPerPixel ?? 1)
          .toList(growable: false),
      width: width,
      height: height,
    );
  }
}
