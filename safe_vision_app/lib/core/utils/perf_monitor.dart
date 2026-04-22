import 'package:flutter/foundation.dart';

/// Lightweight debug-only telemetry for the real-time detection pipeline.
///
/// The monitor tracks:
/// - dispatched frames: frames actually sent to inference
/// - latest-frame queue/refresh operations while inference is busy
/// - busy skips: frames intentionally ignored because a fresher pending frame
///   is already waiting
/// - dropped frames: stale frames that expired before they could be processed
/// - throttled frames: frames skipped by any explicit FPS limiter
/// - inference latency
/// - completed detection FPS
class PerfMonitor {
  PerfMonitor._();

  static final List<int> _dispatchTimes = <int>[];
  static final List<int> _completionTimes = <int>[];
  static final List<int> _inferenceTimes = <int>[];

  static int _latestFrameQueued = 0;
  static int _latestFrameRefreshes = 0;
  static int _busySkippedFrames = 0;
  static int _droppedFrames = 0;
  static int _throttledFrames = 0;
  static DateTime? _lastReport;

  static void frameDispatched() {
    if (!kDebugMode) return;
    _dispatchTimes.add(DateTime.now().millisecondsSinceEpoch);
    if (_dispatchTimes.length > 60) _dispatchTimes.removeAt(0);
    _maybeReport();
  }

  static void latestFrameQueued() {
    if (!kDebugMode) return;
    _latestFrameQueued++;
  }

  static void latestFrameRefreshed() {
    if (!kDebugMode) return;
    _latestFrameRefreshes++;
  }

  static void frameSkippedWhileBusy() {
    if (!kDebugMode) return;
    _busySkippedFrames++;
  }

  static void frameThrottled() {
    if (!kDebugMode) return;
    _throttledFrames++;
  }

  static void frameDropped() {
    if (!kDebugMode) return;
    _droppedFrames++;
  }

  static void inferenceCompleted(int latencyMs) {
    if (!kDebugMode) return;
    _inferenceTimes.add(latencyMs);
    if (_inferenceTimes.length > 30) _inferenceTimes.removeAt(0);

    _completionTimes.add(DateTime.now().millisecondsSinceEpoch);
    if (_completionTimes.length > 30) _completionTimes.removeAt(0);

    _maybeReport();
  }

  static void _maybeReport() {
    final now = DateTime.now();
    if (_lastReport != null && now.difference(_lastReport!).inSeconds < 5) {
      return;
    }
    _lastReport = now;

    final detectionFps = _fpsFrom(_completionTimes);
    final dispatchFps = _fpsFrom(_dispatchTimes);
    final avgInference = _inferenceTimes.isEmpty
        ? '?'
        : (_inferenceTimes.reduce((a, b) => a + b) / _inferenceTimes.length)
            .toStringAsFixed(0);

    debugPrint(
      '[PerfMonitor] dispatch≈$dispatchFps fps | '
      'detections≈$detectionFps fps | '
      'inference≈${avgInference}ms | '
      'queued=$_latestFrameQueued | '
      'refreshed=$_latestFrameRefreshes | '
      'busySkip=$_busySkippedFrames | '
      'throttled=$_throttledFrames | '
      'dropped=$_droppedFrames',
    );
  }

  static String _fpsFrom(List<int> samples) {
    if (samples.length < 2) return '?';
    final gaps = <int>[];
    for (int i = 1; i < samples.length; i++) {
      gaps.add(samples[i] - samples[i - 1]);
    }
    final avgGap = gaps.reduce((a, b) => a + b) / gaps.length;
    return avgGap > 0 ? (1000 / avgGap).toStringAsFixed(1) : '?';
  }

  static void reset() {
    _dispatchTimes.clear();
    _completionTimes.clear();
    _inferenceTimes.clear();
    _latestFrameQueued = 0;
    _latestFrameRefreshes = 0;
    _busySkippedFrames = 0;
    _droppedFrames = 0;
    _throttledFrames = 0;
    _lastReport = null;
  }
}
