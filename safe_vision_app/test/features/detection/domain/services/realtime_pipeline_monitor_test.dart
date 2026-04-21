import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/features/detection/domain/services/realtime_pipeline_monitor.dart';

void main() {
  group('RealtimePipelineMonitor', () {
    test('tracks fps, drops and inference latencies', () {
      final monitor = RealtimePipelineMonitor();
      monitor.onFrameDropped(PipelineDropReason.busy);
      monitor.onFrameDropped(PipelineDropReason.throttled);

      monitor.onFrameProcessed(nowMs: 1000, inferenceMs: 40);
      monitor.onFrameProcessed(nowMs: 1300, inferenceMs: 20);

      final metrics = monitor.snapshot(1300);
      expect(metrics.processedFrames, 2);
      expect(metrics.droppedFramesBusy, 1);
      expect(metrics.droppedFramesThrottled, 1);
      expect(metrics.lastInferenceMs, 20);
      expect(metrics.avgInferenceMs, closeTo(30, 0.0001));
      expect(metrics.fps, greaterThan(0));
    });

    test('tracks alerts per minute', () {
      final monitor = RealtimePipelineMonitor();
      monitor.onAlertSent(0);
      monitor.onAlertSent(1000);
      monitor.onAlertSent(2000);

      final metrics = monitor.snapshot(2000);
      expect(metrics.alertsPerMinute, greaterThanOrEqualTo(3));
    });
  });
}
