import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Lightweight rolling-average performance monitor for the inference pipeline.
///
/// Records frame latencies and exposes [avgLatencyMs] and [fps] for the
/// debug overlay.  All methods are no-ops in release builds.
class PerfMonitor {
  PerfMonitor({this.windowSize = 30});

  final int windowSize;

  final Queue<int> _latencies = Queue();
  DateTime? _frameStart;
  int _droppedFrames = 0;

  // ── Recording ─────────────────────────────────────────────────────────────

  void frameStarted() {
    if (!kDebugMode) return;
    _frameStart = DateTime.now();
  }

  void frameCompleted() {
    if (!kDebugMode) return;
    if (_frameStart == null) return;
    final ms = DateTime.now().difference(_frameStart!).inMilliseconds;
    _frameStart = null;
    _latencies.addLast(ms);
    if (_latencies.length > windowSize) _latencies.removeFirst();
  }

  void frameDropped() {
    if (!kDebugMode) return;
    _droppedFrames++;
  }

  void reset() {
    _latencies.clear();
    _frameStart = null;
    _droppedFrames = 0;
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  double get avgLatencyMs {
    if (_latencies.isEmpty) return 0;
    return _latencies.reduce((a, b) => a + b) / _latencies.length;
  }

  double get fps {
    final avg = avgLatencyMs;
    return avg > 0 ? 1000 / avg : 0;
  }

  int get droppedFrames => _droppedFrames;
}
