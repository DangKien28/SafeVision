import 'package:flutter/foundation.dart';

import '../../../../core/models/camera_frame.dart';
import 'detection_local_datasource.dart';

/// Runs primary inference on every frame and falls back to [_fallbackDatasource]
/// when the primary returns an empty result set.
///
/// ## Fallback trigger rules
///
/// The fallback is attempted when ALL of the following are true:
/// 1. [_enableFallback] is `true`.
/// 2. The primary returned an empty list (either normally or by throwing).
/// 3. At least one of:
///    - The primary **threw an exception** (`primaryFailed == true`), OR
///    - The current frame counter is a multiple of [_fallbackIntervalFrames].
///
/// Forcing the fallback on exception (regardless of interval) prevents a
/// silently-failing primary from starving the user of any detections.
///
/// ## Lifecycle
///
/// [closeModel] always closes **both** datasources unconditionally, even when
/// [_enableFallback] is `false`.  This is safe because [closeModel] is a
/// no-op on a datasource that was never loaded.
class HybridDetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  HybridDetectionLocalDatasourceImpl({
    required DetectionLocalDatasource primaryDatasource,
    required DetectionLocalDatasource fallbackDatasource,
    required bool enableFallback,
    required int fallbackIntervalFrames,
  })  : _primaryDatasource = primaryDatasource,
        _fallbackDatasource = fallbackDatasource,
        _enableFallback = enableFallback,
        // Clamp ensures the interval is always a usable positive integer.
        // Values ≤ 0 are not meaningful and would cause every frame to trigger
        // the fallback, defeating the purpose of the interval.
        _fallbackIntervalFrames = fallbackIntervalFrames.clamp(1, 60).toInt();

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

    var primaryFailed = false;
    List<Map<String, dynamic>> primaryResults;
    try {
      primaryResults = await _primaryDatasource.runInference(
        frame,
        rotationDegrees: rotationDegrees,
      );
    } catch (e) {
      debugPrint('[HybridDatasource] primary inference error: $e');
      primaryResults = [];
      primaryFailed = true;
    }

    // Bypass the interval check when the primary threw an exception — a
    // crashing primary should trigger the fallback immediately rather than
    // waiting for the next scheduled interval frame.
    final shouldTryFallback = _enableFallback &&
        primaryResults.isEmpty &&
        (primaryFailed || _frameCounter % _fallbackIntervalFrames == 0);
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
    // Always close both datasources unconditionally.  When _enableFallback is
    // false the fallback datasource was never loaded, but calling closeModel()
    // on an unloaded datasource is defined as a safe no-op by the contract.
    await _primaryDatasource.closeModel();
    await _fallbackDatasource.closeModel();
    _frameCounter = 0;
  }
}