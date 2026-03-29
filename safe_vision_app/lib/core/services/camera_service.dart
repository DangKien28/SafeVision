import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../error/exceptions.dart' as ex;

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentIndex = 0;

  CameraController? get controller  => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isFrontCamera =>
      _cameras.isNotEmpty &&
      _cameras[_currentIndex].lensDirection == CameraLensDirection.front;

  // ── Initialize ────────────────────────────────────────────────────────────

  Future<void> initialize({int cameraIndex = 0}) async {
    // FIX: BỎ guard `if (isInitialized) return;`
    // Guard đó ngăn re-init sau lifecycle events (pause/resume)
    _cameras = await availableCameras();
    if (_cameras.isEmpty) throw const ex.CameraException('Không tìm thấy camera');
    _currentIndex = cameraIndex.clamp(0, _cameras.length - 1);
    await _setupController(_cameras[_currentIndex]);
  }

  Future<void> _setupController(CameraDescription camera) async {
    // Dispose controller cũ
    final old = _controller;
    _controller = null;
    if (old != null) {
      try {
        if (old.value.isStreamingImages) await old.stopImageStream();
        await old.dispose();
      } catch (e) {
        debugPrint('[CameraService] dispose old controller error: $e');
      }
    }

    final ctrl = CameraController(
      camera,
      ResolutionPreset.low,        // buffer nhỏ nhất để giảm OOM
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await ctrl.initialize();
    _controller = ctrl;
    debugPrint('[CameraService] camera ready: ${camera.name} (${camera.lensDirection})');
  }

  // ── Stream ────────────────────────────────────────────────────────────────

  void startImageStream({required void Function(CameraImage) onFrame}) {
    if (_controller == null || !isInitialized) {
      debugPrint('[CameraService] startImageStream: not ready, skip');
      return;
    }
    if (_controller!.value.isStreamingImages) {
      debugPrint('[CameraService] already streaming');
      return;
    }

    DateTime lastProcessed = DateTime(0);
    const minIntervalMs = 300; // ~3fps để inference kịp

    _controller!.startImageStream((CameraImage image) {
      final now = DateTime.now();
      if (now.difference(lastProcessed).inMilliseconds < minIntervalMs) return;
      lastProcessed = now;
      onFrame(image);
    });

    debugPrint('[CameraService] image stream started (throttle ${minIntervalMs}ms)');
  }

  Future<void> stopImageStream() async {
    try {
      if (_controller?.value.isStreamingImages ?? false) {
        await _controller!.stopImageStream();
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
    await stopImageStream();
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }
}