import 'package:equatable/equatable.dart';

import 'detection_object.dart';

/// A tracked detection after temporal matching/smoothing has been applied.
///
/// [trackId] stays stable across frames while IoU matching succeeds.
/// [missedFrames] increases when the track is temporarily not seen.
/// [consecutiveVisibleFrames] counts how many consecutive frames the object has
/// been visible without interruption, which is useful for stable warning logic.
class TrackedDetection extends Equatable {
  const TrackedDetection({
    required this.trackId,
    required this.detection,
    required this.missedFrames,
    required this.consecutiveVisibleFrames,
  });

  final int trackId;
  final DetectionObject detection;
  final int missedFrames;
  final int consecutiveVisibleFrames;

  bool get isVisible => missedFrames == 0;

  @override
  List<Object?> get props => [
        trackId,
        detection,
        missedFrames,
        consecutiveVisibleFrames,
      ];
}
