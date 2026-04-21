import 'package:equatable/equatable.dart';

import '../../domain/entities/detection_object.dart';
import '../../domain/entities/realtime_pipeline_metrics.dart';
import '../../domain/entities/tracked_detection.dart';

/// Base class for all detection pipeline states.
abstract class DetectionState extends Equatable {
  const DetectionState();

  @override
  List<Object?> get props => [];
}

/// Initial state before [DetectionStarted] is dispatched.
class DetectionInitial extends DetectionState {
  const DetectionInitial();
}

/// Transitional state while the TFLite model is loading.
class DetectionLoading extends DetectionState {
  const DetectionLoading();
}

/// The model is loaded and the camera is streaming frames.
class DetectionModelReady extends DetectionState {
  const DetectionModelReady();
}

/// A frame has been processed; [detections] may be empty.
///
/// [timestamp] is milliseconds since epoch; it is included in [props] so that
/// two successive frames with identical detections are still treated as
/// distinct states by BLoC (which would otherwise drop the second emit as a
/// no-op).
///
/// [trackedDetections] is the temporally-stable list produced by
/// [ObjectTracker].  The UI uses these for bounding-box rendering (smooth
/// positions, fade-out on miss) while [detections] is used for TTS warnings.
class DetectionSuccess extends DetectionState {
  const DetectionSuccess({
    required this.detections,
    required this.trackedDetections,
    required this.timestamp,
    this.pipelineMetrics = const RealtimePipelineMetrics.empty(),
  });

  final List<DetectionObject> detections;
  final List<TrackedDetection> trackedDetections;
  final int timestamp;
  final RealtimePipelineMetrics pipelineMetrics;

  @override
  List<Object?> get props =>
      [detections, trackedDetections, timestamp, pipelineMetrics];
}

/// A non-recoverable error occurred (e.g. model file not found).
class DetectionFailure extends DetectionState {
  const DetectionFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
