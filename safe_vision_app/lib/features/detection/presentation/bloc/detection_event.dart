import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/models/camera_frame.dart';

/// Base class for all detection pipeline events.
abstract class DetectionEvent extends Equatable {
  const DetectionEvent();

  @override
  List<Object?> get props => [];
}

/// Fired once to load the TFLite model and start the detection pipeline.
class DetectionStarted extends DetectionEvent {
  const DetectionStarted();
}

/// Fired to tear down the model and stop the pipeline.
class DetectionStopped extends DetectionEvent {
  const DetectionStopped();
}

/// Fired for every camera frame that should be sent to inference.
///
/// ## onDone contract
///
/// [onDone] MUST be called exactly once after the bloc finishes handling this
/// event — whether the frame was processed successfully, dropped by the
/// `droppable()` transformer, or failed with an exception.  [DetectionBloc]
/// wraps all handling paths in a `finally` block to guarantee this.
///
/// Calling [onDone] releases [CameraService]'s `_isProcessingFrame` lock.
/// Failing to call it permanently stalls the camera stream.
class DetectionFrameReceived extends DetectionEvent {
  const DetectionFrameReceived(
    this.frame,
    this.rotationDegrees,
    this.onDone,
  );

  final CameraFrame frame;
  final int rotationDegrees;

  /// Must be called in a finally block after inference completes (or fails).
  final VoidCallback onDone;

  @override
  // onDone is excluded from props intentionally: two events with identical
  // frame data but different callback instances must be treated as distinct
  // events by the droppable transformer.
  List<Object?> get props => [frame, rotationDegrees];
}
