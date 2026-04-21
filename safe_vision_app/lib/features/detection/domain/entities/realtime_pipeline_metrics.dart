import 'package:equatable/equatable.dart';

class RealtimePipelineMetrics extends Equatable {
  const RealtimePipelineMetrics({
    required this.processedFrames,
    required this.droppedFramesBusy,
    required this.droppedFramesThrottled,
    required this.fps,
    required this.lastInferenceMs,
    required this.avgInferenceMs,
    required this.alertsPerMinute,
    required this.lowVisibility,
    required this.visibilityScore,
  });

  const RealtimePipelineMetrics.empty()
      : processedFrames = 0,
        droppedFramesBusy = 0,
        droppedFramesThrottled = 0,
        fps = 0,
        lastInferenceMs = 0,
        avgInferenceMs = 0,
        alertsPerMinute = 0,
        lowVisibility = false,
        visibilityScore = 1;

  final int processedFrames;
  final int droppedFramesBusy;
  final int droppedFramesThrottled;
  final double fps;
  final double lastInferenceMs;
  final double avgInferenceMs;
  final double alertsPerMinute;
  final bool lowVisibility;
  final double visibilityScore;

  int get droppedFramesTotal => droppedFramesBusy + droppedFramesThrottled;

  @override
  List<Object?> get props => [
        processedFrames,
        droppedFramesBusy,
        droppedFramesThrottled,
        fps,
        lastInferenceMs,
        avgInferenceMs,
        alertsPerMinute,
        lowVisibility,
        visibilityScore,
      ];
}
