import 'dart:collection';

import '../entities/realtime_pipeline_metrics.dart';

enum PipelineDropReason { busy, throttled }

class RealtimePipelineMonitor {
  final ListQueue<int> _processedFrameTimesMs = ListQueue<int>();
  final ListQueue<int> _alertTimesMs = ListQueue<int>();

  int _processedFrames = 0;
  int _droppedFramesBusy = 0;
  int _droppedFramesThrottled = 0;
  double _lastInferenceMs = 0;
  double _avgInferenceMs = 0;
  bool _lowVisibility = false;
  double _visibilityScore = 1;

  void onFrameDropped(PipelineDropReason reason) {
    if (reason == PipelineDropReason.busy) {
      _droppedFramesBusy++;
    } else {
      _droppedFramesThrottled++;
    }
  }

  void onFrameProcessed({
    required int nowMs,
    required double inferenceMs,
  }) {
    _processedFrames++;
    _lastInferenceMs = inferenceMs;
    _avgInferenceMs = _processedFrames == 1
        ? inferenceMs
        : (_avgInferenceMs * (_processedFrames - 1) + inferenceMs) /
            _processedFrames;
    _processedFrameTimesMs.addLast(nowMs);
    _trim(_processedFrameTimesMs, nowMs, _kFpsWindowMs);
  }

  void onAlertSent(int nowMs) {
    _alertTimesMs.addLast(nowMs);
    _trim(_alertTimesMs, nowMs, _kAlertsWindowMs);
  }

  void onVisibilityUpdated({
    required bool lowVisibility,
    required double visibilityScore,
  }) {
    _lowVisibility = lowVisibility;
    _visibilityScore = visibilityScore;
  }

  RealtimePipelineMetrics snapshot(int nowMs) {
    _trim(_processedFrameTimesMs, nowMs, _kFpsWindowMs);
    _trim(_alertTimesMs, nowMs, _kAlertsWindowMs);

    final fps = _processedFrameTimesMs.length / (_kFpsWindowMs / 1000);
    final alertsPerMinute = _alertTimesMs.length * (60000 / _kAlertsWindowMs);

    return RealtimePipelineMetrics(
      processedFrames: _processedFrames,
      droppedFramesBusy: _droppedFramesBusy,
      droppedFramesThrottled: _droppedFramesThrottled,
      fps: fps,
      lastInferenceMs: _lastInferenceMs,
      avgInferenceMs: _avgInferenceMs,
      alertsPerMinute: alertsPerMinute,
      lowVisibility: _lowVisibility,
      visibilityScore: _visibilityScore,
    );
  }

  void reset() {
    _processedFrameTimesMs.clear();
    _alertTimesMs.clear();
    _processedFrames = 0;
    _droppedFramesBusy = 0;
    _droppedFramesThrottled = 0;
    _lastInferenceMs = 0;
    _avgInferenceMs = 0;
    _lowVisibility = false;
    _visibilityScore = 1;
  }

  static void _trim(ListQueue<int> q, int nowMs, int windowMs) {
    final minTs = nowMs - windowMs;
    while (q.isNotEmpty && q.first < minTs) {
      q.removeFirst();
    }
  }
}

const int _kFpsWindowMs = 3000;
const int _kAlertsWindowMs = 60000;
