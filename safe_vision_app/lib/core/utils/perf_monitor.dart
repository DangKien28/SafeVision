import 'package:flutter/foundation.dart';

/// Lightweight frame-rate and latency tracker for the detection pipeline.
/// All methods are no-ops in release builds.
class PerfMonitor {
  PerfMonitor._();

  static final _frameTimes = <int>[];
  static final _inferenceTimes = <int>[];
  static int _droppedFrames = 0;
  static DateTime? _lastReport;

  static void frameReceived() {
    if (!kDebugMode) return;
    _frameTimes.add(DateTime.now().millisecondsSinceEpoch);
    if (_frameTimes.length > 60) _frameTimes.removeAt(0);
    _maybeReport();
  }

  static void frameDropped() {
    if (!kDebugMode) return;
    _droppedFrames++;
  }

  static void inferenceCompleted(int latencyMs) {
    if (!kDebugMode) return;
    _inferenceTimes.add(latencyMs);
    if (_inferenceTimes.length > 30) _inferenceTimes.removeAt(0);
  }

  static void _maybeReport() {
    final now = DateTime.now();
    if (_lastReport != null && now.difference(_lastReport!).inSeconds < 5) {
      return;
    }
    _lastReport = now;

    if (_frameTimes.length < 2) return;

    final gaps = <int>[];
    for (int i = 1; i < _frameTimes.length; i++) {
      gaps.add(_frameTimes[i] - _frameTimes[i - 1]);
    }
    final avgGap = gaps.reduce((a, b) => a + b) / gaps.length;
    final fps = avgGap > 0 ? (1000 / avgGap).toStringAsFixed(1) : '?';

    final avgInference = _inferenceTimes.isEmpty
        ? '?'
        : (_inferenceTimes.reduce((a, b) => a + b) / _inferenceTimes.length)
            .toStringAsFixed(0);

    debugPrint(
      '[PerfMonitor] FPS≈$fps | '
      'inference≈${avgInference}ms | '
      'dropped=$_droppedFrames',
    );
  }

  static void reset() {
    _frameTimes.clear();
    _inferenceTimes.clear();
    _droppedFrames = 0;
    _lastReport = null;
  }
}
