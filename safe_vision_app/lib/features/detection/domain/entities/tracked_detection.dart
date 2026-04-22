import 'package:equatable/equatable.dart';

import 'detection_object.dart';

enum TrackedDetectionPhase { tentative, active, fading }

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
    required this.phase,
  });

  final int trackId;
  final DetectionObject detection;
  final int missedFrames;
  final int consecutiveVisibleFrames;
  final TrackedDetectionPhase phase;

  bool get isVisible => missedFrames == 0;
  bool get isConfirmed =>
      phase == TrackedDetectionPhase.active ||
      phase == TrackedDetectionPhase.fading;
  bool get isAnnounceable =>
      phase == TrackedDetectionPhase.active && missedFrames == 0;
  bool get isRenderable =>
      phase != TrackedDetectionPhase.tentative || isVisible;

  @override
  List<Object?> get props => [
        trackId,
        detection,
        missedFrames,
        consecutiveVisibleFrames,
        phase,
      ];
}
