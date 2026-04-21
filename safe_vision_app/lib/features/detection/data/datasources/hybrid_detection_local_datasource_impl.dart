import 'package:flutter/foundation.dart';

import '../../../../core/models/camera_frame.dart';
import 'detection_local_datasource.dart';

class HybridDetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  HybridDetectionLocalDatasourceImpl({
    required DetectionLocalDatasource primaryDatasource,
    required DetectionLocalDatasource fallbackDatasource,
    required bool enableFallback,
    required int fallbackIntervalFrames,
  })  : _primaryDatasource = primaryDatasource,
        _fallbackDatasource = fallbackDatasource,
        _enableFallback = enableFallback,
        _fallbackIntervalFrames =
            fallbackIntervalFrames < 1 ? 1 : fallbackIntervalFrames;

  final DetectionLocalDatasource _primaryDatasource;
  final DetectionLocalDatasource _fallbackDatasource;
  final bool _enableFallback;
  final int _fallbackIntervalFrames;
  int _frameCounter = 0;

  @override
  Future<void> loadModel() async {
    await _primaryDatasource.loadModel();
    if (_enableFallback) {
      await _fallbackDatasource.loadModel();
    }
    _frameCounter = 0;
  }

  @override
  Future<List<Map<String, dynamic>>> runInference(
    CameraFrame frame, {
    required int rotationDegrees,
  }) async {
    _frameCounter++;

    List<Map<String, dynamic>> primaryResults;
    try {
      primaryResults = await _primaryDatasource.runInference(
        frame,
        rotationDegrees: rotationDegrees,
      );
    } catch (e) {
      debugPrint('[HybridDatasource] primary inference error: $e');
      primaryResults = [];
    }

    final shouldTryFallback = _enableFallback &&
        primaryResults.isEmpty &&
        (_frameCounter % _fallbackIntervalFrames == 0);
    if (!shouldTryFallback) return primaryResults;

    try {
      final fallbackResults = await _fallbackDatasource.runInference(
        frame,
        rotationDegrees: rotationDegrees,
      );
      return fallbackResults.isEmpty ? primaryResults : fallbackResults;
    } catch (e) {
      debugPrint('[HybridDatasource] fallback inference error: $e');
      return primaryResults;
    }
  }

  @override
  Future<void> closeModel() async {
    await _primaryDatasource.closeModel();
    if (_enableFallback) {
      await _fallbackDatasource.closeModel();
    }
    _frameCounter = 0;
  }
}
