import 'dart:math';

import '../../../../core/constants/app_constants.dart';
import '../entities/detection_object.dart';
import '../entities/tracked_detection.dart';

/// Tracks detections across consecutive frames using greedy IoU matching.
///
/// The tracker owns the temporal state so both UI smoothing and warning logic
/// can use the same object identity model instead of reimplementing separate
/// matching rules in different layers.
///
/// ## Label-relaxed matching
/// When a detection overlaps an existing track with IoU > [_iouOverrideThreshold],
/// the track is matched even if the label differs. This prevents spurious new
/// tracks when a weak model oscillates between class labels for the same physical
/// object (e.g., flickering between '100k' and '200k' for the same banknote).
/// A small [_crossLabelPenalty] is applied to prefer same-label matches when
/// both are available. The track label is updated when the incoming detection
/// is significantly more confident than the tracked confidence.
class ObjectTracker {
  final Map<int, _TrackedBox> _tracked = {};
  int _nextTrackId = 0;

  int _version = 0;
  int get version => _version;

  static const double _alpha = AppConstants.trackingSmoothingAlpha;
  static const double _matchScoreThreshold = 0.45;
  static const double _minIouForDirectMatch = 0.20;
  static const double _maxCenterDistance = 0.18;
  static const double _minAreaSimilarity = 0.35;
  static const int _confirmFrames = AppConstants.trackingConfirmFrames;
  static const int _maxMissedFrames = AppConstants.trackingMaxMissedFrames;
  static const Duration _maxTrackAge =
      Duration(milliseconds: AppConstants.trackingMaxAgeMs);

  // FIX RC-4: Allow cross-label match when spatial overlap is very high.
  // A model that flip-flops labels for the same physical object should update
  // the existing track instead of spawning a parallel one.
  static const double _iouOverrideThreshold = 0.55;
  static const double _crossLabelPenalty = 0.15;
  // Confidence margin required for the new detection to override track label.
  static const double _labelUpdateConfidenceMargin = 0.15;

  List<TrackedDetection> update(
    List<DetectionObject> detections, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    final usedTrackIds = <int>{};
    for (final detection in detections) {
      int? bestTrackId;
      double bestScore = -1;

      for (final entry in _tracked.entries) {
        final tracked = entry.value;
        if (tracked.label != detection.label) continue;
        if (usedTrackIds.contains(entry.key)) continue;
        final score = _matchScore(tracked, detection);
        if (score > bestScore) {
          bestScore = score;
          bestTrackId = entry.key;
        }
      }

      if (bestTrackId != null && bestScore >= _matchScoreThreshold) {
        _tracked[bestTrackId]!.update(
          detection,
          timestamp,
          confirmFrames: _confirmFrames,
        );
        usedTrackIds.add(bestTrackId);
      } else {
        final trackId = _nextTrackId++;
        _tracked[trackId] = _TrackedBox.fromDetection(
          trackId: trackId,
          detection: detection,
          lastSeenAt: timestamp,
          confirmFrames: _confirmFrames,
        );
        usedTrackIds.add(trackId);
      }
    }

    for (final entry in _tracked.entries) {
      if (!usedTrackIds.contains(entry.key)) {
        entry.value.markMissed();
      }
    }

    _tracked.removeWhere(
      (_, tracked) => tracked.shouldEvict(
        timestamp,
        maxAge: _maxTrackAge,
        maxMissedFrames: _maxMissedFrames,
      ),
    );

    _version++;
    return _tracked.values
        .where((tracked) => tracked.isRenderable)
        .map((tracked) => tracked.snapshot())
        .toList(growable: false)
      ..sort((a, b) => a.trackId.compareTo(b.trackId));
  }

  void clear() {
    _tracked.clear();
    _nextTrackId = 0;
    _version++;
  }

  double _matchScore(_TrackedBox tracked, DetectionObject detection) {
    final box = detection.boundingBox;
    final iou = _iou(
      tracked.left,
      tracked.top,
      tracked.width,
      tracked.height,
      box.left,
      box.top,
      box.width,
      box.height,
    );

    final labelMatches = tracked.label == detection.label;

    // FIX RC-4: High spatial overlap (IoU > threshold) indicates the same
    // physical object even when the model oscillates between class labels.
    // Allow the match but apply a penalty so same-label tracks are preferred.
    final iouOverride = iou > _iouOverrideThreshold;
    if (!labelMatches && !iouOverride) return -1;

    final trackedCenterX = tracked.left + tracked.width / 2;
    final trackedCenterY = tracked.top + tracked.height / 2;
    final centerDx = trackedCenterX - box.centerX;
    final centerDy = trackedCenterY - box.centerY;
    final centerDistance = sqrt(centerDx * centerDx + centerDy * centerDy);
    final centerScore = (1.0 - (centerDistance / _maxCenterDistance))
        .clamp(0.0, 1.0)
        .toDouble();

    final trackedArea = tracked.width * tracked.height;
    final incomingArea = box.area;
    final largerArea = trackedArea > incomingArea ? trackedArea : incomingArea;
    final smallerArea = trackedArea < incomingArea ? trackedArea : incomingArea;
    final areaSimilarity =
        largerArea <= 0 ? 0.0 : (smallerArea / largerArea).clamp(0.0, 1.0);

    final compatible = iou >= _minIouForDirectMatch ||
        (centerScore >= 0.55 && areaSimilarity >= _minAreaSimilarity);
    if (!compatible) return -1;

    final phaseBias =
        tracked.phase == TrackedDetectionPhase.active ? 0.05 : 0.0;
    // Apply penalty for cross-label match so same-label tracks are preferred.
    final labelBonus = labelMatches ? 0.0 : -_crossLabelPenalty;
    return iou * 0.7 + centerScore * 0.2 + areaSimilarity * 0.1 + phaseBias +
        labelBonus;
  }

  double _iou(
    double al,
    double at,
    double aw,
    double ah,
    double bl,
    double bt,
    double bw,
    double bh,
  ) {
    final iL = al > bl ? al : bl;
    final iT = at > bt ? at : bt;
    final iR = (al + aw) < (bl + bw) ? (al + aw) : (bl + bw);
    final iB = (at + ah) < (bt + bh) ? (at + ah) : (bt + bh);
    if (iR <= iL || iB <= iT) return 0;
    final inter = (iR - iL) * (iB - iT);
    return inter / (aw * ah + bw * bh - inter);
  }
}

class _TrackedBox {
  _TrackedBox({
    required this.trackId,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.label,
    required this.confidence,
    required this.lastSeenAt,
    required this.missedFrames,
    required this.consecutiveVisibleFrames,
    required this.phase,
    required this.hasConfirmedOnce,
  });

  factory _TrackedBox.fromDetection({
    required int trackId,
    required DetectionObject detection,
    required DateTime lastSeenAt,
    required int confirmFrames,
  }) {
    final box = detection.boundingBox;
    final initialVisibleFrames = 1;
    final confirmed = initialVisibleFrames >= confirmFrames;
    return _TrackedBox(
      trackId: trackId,
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      label: detection.label,
      confidence: detection.confidence,
      lastSeenAt: lastSeenAt,
      missedFrames: 0,
      consecutiveVisibleFrames: initialVisibleFrames,
      phase: confirmed
          ? TrackedDetectionPhase.active
          : TrackedDetectionPhase.tentative,
      hasConfirmedOnce: confirmed,
    );
  }

  final int trackId;
  double left;
  double top;
  double width;
  double height;
  // FIX RC-4: Non-final label allows the tracker to update when the model
  // consistently produces a higher-confidence label for the same spatial track.
  String label;
  double confidence;
  DateTime lastSeenAt;
  int missedFrames;
  int consecutiveVisibleFrames;
  TrackedDetectionPhase phase;
  bool hasConfirmedOnce;

  bool get isRenderable =>
      phase != TrackedDetectionPhase.tentative || missedFrames == 0;

  void markMissed() {
    missedFrames++;
    if (missedFrames == 1) {
      consecutiveVisibleFrames = 0;
    }
    if (phase == TrackedDetectionPhase.active && missedFrames > 0) {
      phase = TrackedDetectionPhase.fading;
    }
  }

  void update(
    DetectionObject detection,
    DateTime now, {
    required int confirmFrames,
  }) {
    final box = detection.boundingBox;
    final recoveredAfterMiss = missedFrames > 0;
    left = left * (1 - ObjectTracker._alpha) + box.left * ObjectTracker._alpha;
    top = top * (1 - ObjectTracker._alpha) + box.top * ObjectTracker._alpha;
    width =
        width * (1 - ObjectTracker._alpha) + box.width * ObjectTracker._alpha;
    height =
        height * (1 - ObjectTracker._alpha) + box.height * ObjectTracker._alpha;

    // FIX RC-4: When a cross-label match occurs and the new detection is
    // significantly more confident, update the track label so that the bounding
    // box, ConfidenceScoreDisplay and TTS voice all reference the same label.
    if (detection.label != label &&
        detection.confidence > confidence + ObjectTracker._labelUpdateConfidenceMargin) {
      label = detection.label;
    }

    confidence = confidence * 0.3 + detection.confidence * 0.7;
    missedFrames = 0;
    consecutiveVisibleFrames =
        recoveredAfterMiss ? 1 : consecutiveVisibleFrames + 1;
    if (hasConfirmedOnce || consecutiveVisibleFrames >= confirmFrames) {
      hasConfirmedOnce = true;
      phase = TrackedDetectionPhase.active;
    } else {
      phase = TrackedDetectionPhase.tentative;
    }
    lastSeenAt = now;
  }

  bool shouldEvict(
    DateTime now, {
    required Duration maxAge,
    required int maxMissedFrames,
  }) {
    if (phase == TrackedDetectionPhase.tentative && missedFrames > 0) {
      return true;
    }
    if (missedFrames > maxMissedFrames) {
      return true;
    }
    return now.difference(lastSeenAt) > maxAge;
  }

  TrackedDetection snapshot() {
    return TrackedDetection(
      trackId: trackId,
      detection: DetectionObject(
        label: label,
        confidence: confidence,
        boundingBox: BoundingBox(
          left: left,
          top: top,
          width: width,
          height: height,
        ),
      ),
      missedFrames: missedFrames,
      consecutiveVisibleFrames: consecutiveVisibleFrames,
      phase: phase,
    );
  }
}
