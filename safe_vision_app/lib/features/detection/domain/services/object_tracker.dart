import '../../../../core/constants/app_constants.dart';
import '../entities/detection_object.dart';
import '../entities/tracked_detection.dart';

/// Tracks detections across consecutive frames using greedy IoU matching.
///
/// The tracker owns the temporal state so both UI smoothing and warning logic
/// can use the same object identity model instead of reimplementing separate
/// matching rules in different layers.
class ObjectTracker {
  final Map<int, _TrackedBox> _tracked = {};
  int _nextTrackId = 0;

  int _version = 0;
  int get version => _version;

  static const double _alpha = AppConstants.trackingSmoothingAlpha;
  static const double _matchThreshold = 0.35;
  static const Duration _maxTrackAge =
      Duration(milliseconds: AppConstants.trackingMaxAgeMs);

  List<TrackedDetection> update(
    List<DetectionObject> detections, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    for (final tracked in _tracked.values) {
      tracked.missedFrames++;
    }

    final usedTrackIds = <int>{};
    for (final detection in detections) {
      final box = detection.boundingBox;
      int? bestTrackId;
      double bestIou = 0;

      for (final entry in _tracked.entries) {
        final tracked = entry.value;
        if (tracked.label != detection.label) continue;
        if (usedTrackIds.contains(entry.key)) continue;

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
        if (iou > bestIou) {
          bestIou = iou;
          bestTrackId = entry.key;
        }
      }

      if (bestTrackId != null && bestIou > _matchThreshold) {
        _tracked[bestTrackId]!.update(detection, timestamp);
        usedTrackIds.add(bestTrackId);
      } else {
        final trackId = _nextTrackId++;
        _tracked[trackId] = _TrackedBox.fromDetection(
          trackId: trackId,
          detection: detection,
          lastSeenAt: timestamp,
        );
        usedTrackIds.add(trackId);
      }
    }

    _tracked.removeWhere(
      (_, tracked) => timestamp.difference(tracked.lastSeenAt) > _maxTrackAge,
    );
    for (final tracked in _tracked.values) {
      if (tracked.missedFrames > 0) {
        tracked.consecutiveVisibleFrames = 0;
      }
    }

    _version++;
    return _tracked.values
        .map((tracked) => tracked.snapshot())
        .toList(growable: false)
      ..sort((a, b) => a.trackId.compareTo(b.trackId));
  }

  void clear() {
    _tracked.clear();
    _nextTrackId = 0;
    _version++;
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
  });

  factory _TrackedBox.fromDetection({
    required int trackId,
    required DetectionObject detection,
    required DateTime lastSeenAt,
  }) {
    final box = detection.boundingBox;
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
      consecutiveVisibleFrames: 1,
    );
  }

  final int trackId;
  double left;
  double top;
  double width;
  double height;
  final String label;
  double confidence;
  DateTime lastSeenAt;
  int missedFrames;
  int consecutiveVisibleFrames;

  void update(DetectionObject detection, DateTime now) {
    final box = detection.boundingBox;
    left = left * (1 - ObjectTracker._alpha) + box.left * ObjectTracker._alpha;
    top = top * (1 - ObjectTracker._alpha) + box.top * ObjectTracker._alpha;
    width =
        width * (1 - ObjectTracker._alpha) + box.width * ObjectTracker._alpha;
    height =
        height * (1 - ObjectTracker._alpha) + box.height * ObjectTracker._alpha;
    confidence = detection.confidence;
    missedFrames = 0;
    consecutiveVisibleFrames++;
    lastSeenAt = now;
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
    );
  }
}
