import '../../../../core/constants/app_constants.dart';
import '../entities/tracked_detection.dart';

/// A normalized warning request produced after applying temporal and semantic
/// filtering on the current tracked detections.
class DetectionWarningAction {
  const DetectionWarningAction({
    required this.text,
    required this.immediate,
    required this.withVibration,
  });

  final String text;
  final bool immediate;
  final bool withVibration;
}

/// Decides when the app should speak about a tracked detection.
///
/// The policy intentionally works on top of tracking output rather than raw
/// detections so warning cadence stays stable even when model confidence
/// fluctuates between neighboring frames.
class WarningPolicy {
  final Map<int, _TrackAnnouncement> _trackAnnouncements =
      <int, _TrackAnnouncement>{};
  final Map<String, DateTime> _semanticAnnouncements = <String, DateTime>{};

  String? _lastAnnouncementKey;
  DateTime? _lastAnnouncementAt;

  DetectionWarningAction? evaluate(
    List<TrackedDetection> trackedDetections, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    final visibleTrackIds = trackedDetections
        .where((tracked) => tracked.isRenderable)
        .map((tracked) => tracked.trackId)
        .toSet();
    _trackAnnouncements.removeWhere(
      (trackId, _) => !visibleTrackIds.contains(trackId),
    );

    final candidates = trackedDetections
        .where((tracked) => tracked.isAnnounceable)
        .map(_WarningCandidate.fromTrackedDetection)
        .where(
          (candidate) =>
              candidate.consecutiveVisibleFrames >=
              candidate.requiredStableFrames,
        )
        .toList(growable: false);

    if (candidates.isEmpty) return null;

    final ranked = candidates.toList(growable: true)
      ..sort((a, b) => b.rank.compareTo(a.rank));
    final top = ranked.first;

    if (!_shouldAnnounce(top, timestamp)) return null;

    _trackAnnouncements[top.trackId] = _TrackAnnouncement(
      semanticKey: top.semanticKey,
      sentAt: timestamp,
      priority: top.priority,
      immediate: top.immediate,
    );
    _semanticAnnouncements[top.semanticKey] = timestamp;
    _lastAnnouncementKey = top.semanticKey;
    _lastAnnouncementAt = timestamp;

    return DetectionWarningAction(
      text: top.text,
      immediate: top.immediate,
      withVibration: top.immediate,
    );
  }

  void reset() {
    _trackAnnouncements.clear();
    _semanticAnnouncements.clear();
    _lastAnnouncementAt = null;
    _lastAnnouncementKey = null;
  }

  bool _shouldAnnounce(_WarningCandidate candidate, DateTime now) {
    final previousTrack = _trackAnnouncements[candidate.trackId];
    final perTrackGapMs = candidate.immediate
        ? AppConstants.dangerWarningRepeatMs
        : AppConstants.warningRepeatMs;

    if (previousTrack != null) {
      final elapsedMs = now.difference(previousTrack.sentAt).inMilliseconds;
      final sameSemantic = previousTrack.semanticKey == candidate.semanticKey;

      if (sameSemantic && elapsedMs < perTrackGapMs) {
        return false;
      }

      if (!sameSemantic &&
          elapsedMs < AppConstants.warningStateChangeMinMs &&
          candidate.priority <= previousTrack.priority) {
        return false;
      }

      if (!candidate.immediate &&
          previousTrack.immediate &&
          elapsedMs < perTrackGapMs) {
        return false;
      }
    }

    final previousSemanticAt = _semanticAnnouncements[candidate.semanticKey];
    if (previousSemanticAt != null) {
      final semanticGapMs = candidate.immediate
          ? AppConstants.dangerWarningRepeatMs
          : AppConstants.warningSemanticRepeatMs;
      if (now.difference(previousSemanticAt).inMilliseconds < semanticGapMs) {
        return false;
      }
    }

    if (_lastAnnouncementKey == candidate.semanticKey &&
        _lastAnnouncementAt != null) {
      final semanticGapMs = candidate.immediate
          ? AppConstants.dangerWarningRepeatMs
          : AppConstants.warningSemanticRepeatMs;
      if (now.difference(_lastAnnouncementAt!).inMilliseconds < semanticGapMs) {
        return false;
      }
    }

    return true;
  }
}

class _WarningCandidate {
  const _WarningCandidate({
    required this.trackId,
    required this.text,
    required this.semanticKey,
    required this.priority,
    required this.rank,
    required this.immediate,
    required this.consecutiveVisibleFrames,
    required this.requiredStableFrames,
  });

  factory _WarningCandidate.fromTrackedDetection(TrackedDetection tracked) {
    final detection = tracked.detection;
    final box = detection.boundingBox;
    final area = box.area;

    final zoneKey = box.centerX < 0.33
        ? 'left'
        : box.centerX > 0.67
            ? 'right'
            : 'center';
    final proximityKey = area > 0.25
        ? 'very_near'
        : area > 0.10
            ? 'near'
            : area > 0.03
                ? 'mid'
                : 'far';

    final immediate = area >= AppConstants.criticalDangerAreaThreshold;
    final priority = immediate
        ? 3
        : detection.isDangerous
            ? 2
            : 1;
    final requiredStableFrames = immediate
        ? AppConstants.dangerWarningStableVisibleFrames
        : AppConstants.warningStableVisibleFrames;

    return _WarningCandidate(
      trackId: tracked.trackId,
      text: detection.voiceWarning,
      semanticKey: '${detection.label}|$zoneKey|$proximityKey',
      priority: priority,
      rank: priority * 1000 +
          (area * 100).round() +
          (detection.confidence * 10).round() +
          tracked.consecutiveVisibleFrames.clamp(0, 12),
      immediate: immediate,
      consecutiveVisibleFrames: tracked.consecutiveVisibleFrames,
      requiredStableFrames: requiredStableFrames,
    );
  }

  final int trackId;
  final String text;
  final String semanticKey;
  final int priority;
  final int rank;
  final bool immediate;
  final int consecutiveVisibleFrames;
  final int requiredStableFrames;
}

class _TrackAnnouncement {
  const _TrackAnnouncement({
    required this.semanticKey,
    required this.sentAt,
    required this.priority,
    required this.immediate,
  });

  final String semanticKey;
  final DateTime sentAt;
  final int priority;
  final bool immediate;
}
