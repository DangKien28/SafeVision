import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/voice_helper.dart';
import '../../domain/entities/detection_object.dart';
import '../../domain/entities/tracked_detection.dart';

// ── SmoothedBox ───────────────────────────────────────────────────────────────

/// An immutable snapshot of a tracked bounding box ready for rendering.
///
/// Coordinates are normalised [0, 1] relative to the preview widget dimensions.
/// [missedFrames] is the number of consecutive frames since the underlying
/// detection was last matched to this track; the painter uses it to fade the
/// box out smoothly before the track expires.
class SmoothedBox {
  const SmoothedBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.label,
    required this.trackId,
    required this.missedFrames,
  });

  /// Converts an [ObjectTracker]-produced [TrackedDetection] into the
  /// rendering-ready [SmoothedBox] format that [BoundingBoxPainter] expects.
  factory SmoothedBox.fromTrackedDetection(TrackedDetection td) {
    final box = td.detection.boundingBox;
    return SmoothedBox(
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      label: td.detection.label,
      trackId: td.trackId,
      missedFrames: td.missedFrames,
    );
  }

  final double left;
  final double top;
  final double width;
  final double height;
  final String label;
  final int trackId;
  final int missedFrames;
}

// ── BoxTracker ────────────────────────────────────────────────────────────────

/// Matches incoming [DetectionObject] lists to persistent tracks via IoU,
/// applies exponential position smoothing, and produces [SmoothedBox] lists
/// for the painter.
///
/// ## Smoothing
///
/// Position is blended each frame:
///   `smoothed = α * detected + (1-α) * tracked`
/// where α = [AppConstants.trackingSmoothingAlpha].
///
/// ## Age-based expiry
///
/// Tracks that have not been matched for [AppConstants.trackingMaxAgeMs]
/// milliseconds are removed from the active set.  The [now] parameter on
/// [update] can be injected in tests to control the clock.
///
/// ## version counter
///
/// An O(1) monotonic integer that increments on every [update] and [clear].
/// [BoundingBoxPainter.shouldRepaint] compares versions directly instead of
/// iterating the box list.
class BoxTracker {
  BoxTracker();

  final Map<int, _Track> _tracks = {};
  int _nextTrackId = 1;
  int _version = 0;

  static const double _iouThreshold = 0.3;

  int get version => _version;

  /// Matches [detections] against active tracks and returns the current
  /// [SmoothedBox] list.  Pass [now] in tests to control the clock.
  List<SmoothedBox> update(
    List<DetectionObject> detections, {
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    _version++;

    // ── 1. Age-out stale tracks ─────────────────────────────────────────────
    final maxAge = AppConstants.trackingMaxAgeMs;
    _tracks.removeWhere(
      (_, t) => time.difference(t.lastSeen).inMilliseconds > maxAge,
    );

    // ── 2. Greedy IoU matching ──────────────────────────────────────────────
    final matched = <int>{}; // detection indices
    final updatedTracks = <int>{}; // track IDs

    for (final entry in _tracks.entries) {
      final track = entry.value;
      double bestIou = _iouThreshold;
      int bestIdx = -1;

      for (int i = 0; i < detections.length; i++) {
        if (matched.contains(i)) continue;
        final iou = _iou(track.box, detections[i].boundingBox);
        if (iou > bestIou) {
          bestIou = iou;
          bestIdx = i;
        }
      }

      if (bestIdx >= 0) {
        // Match found: smooth position and reset miss counter.
        matched.add(bestIdx);
        updatedTracks.add(entry.key);
        final det = detections[bestIdx];
        track.smooth(det.boundingBox, time);
        track.missedFrames = 0;
      } else {
        // No match: increment miss counter.
        track.missedFrames++;
      }
    }

    // ── 3. Spawn new tracks for unmatched detections ────────────────────────
    for (int i = 0; i < detections.length; i++) {
      if (matched.contains(i)) continue;
      final det = detections[i];
      _tracks[_nextTrackId] = _Track(
        id: _nextTrackId,
        box: det.boundingBox,
        label: det.label,
        firstSeen: time,
        lastSeen: time,
      );
      _nextTrackId++;
    }

    // ── 4. Build output ─────────────────────────────────────────────────────
    return _tracks.values.map((t) => t.toSmoothedBox()).toList();
  }

  /// Clears all tracks and increments the version.
  void clear() {
    _tracks.clear();
    _version++;
  }

  // ── IoU helper ──────────────────────────────────────────────────────────────

  static double _iou(BoundingBox a, BoundingBox b) {
    final ix = _overlap(a.left, a.right, b.left, b.right);
    final iy = _overlap(a.top, a.bottom, b.top, b.bottom);
    if (ix <= 0 || iy <= 0) return 0.0;
    final inter = ix * iy;
    return inter / (a.area + b.area - inter);
  }

  static double _overlap(double a0, double a1, double b0, double b1) =>
      (a1 < b1 ? a1 : b1) - (a0 > b0 ? a0 : b0);
}

// ── Internal track state ──────────────────────────────────────────────────────

class _Track {
  _Track({
    required this.id,
    required BoundingBox box,
    required this.label,
    required this.firstSeen,
    required this.lastSeen, // FIX 13: was `required DateTime lastSeen`
  })  : _left = box.left,
        _top = box.top,
        _width = box.width,
        _height = box.height,
        missedFrames = 0;
  // FIX 13: removed `lastSeen = lastSeen,` from init list

  final int id;
  final String label;
  final DateTime firstSeen;
  DateTime lastSeen; // FIX 13: must remain mutable (updated in smooth())
  int missedFrames;

  double _left;
  double _top;
  double _width;
  double _height;

  /// Synthesised [BoundingBox] view of the current smoothed position,
  /// used by [BoxTracker._iou] for greedy matching.
  BoundingBox get box => BoundingBox(
        left: _left,
        top: _top,
        width: _width,
        height: _height,
      );

  static const double _alpha = AppConstants.trackingSmoothingAlpha;

  /// Exponential smoothing toward the new detection position.
  void smooth(BoundingBox detected, DateTime now) {
    _left = _alpha * detected.left + (1 - _alpha) * _left;
    _top = _alpha * detected.top + (1 - _alpha) * _top;
    _width = _alpha * detected.width + (1 - _alpha) * _width;
    _height = _alpha * detected.height + (1 - _alpha) * _height;
    lastSeen = now;
  }

  SmoothedBox toSmoothedBox() => SmoothedBox(
        left: _left,
        top: _top,
        width: _width,
        height: _height,
        label: label,
        trackId: id,
        missedFrames: missedFrames,
      );
}

// ── BoundingBoxPainter ────────────────────────────────────────────────────────

/// Renders [SmoothedBox] bounding boxes on a [CustomPaint] surface.
///
/// ## Performance invariants
///
/// * [shouldRepaint] is O(1): it compares [version] integers, never iterates
///   the box list.
/// * [TextPainter] instances are cached in the static [_textCache] keyed by
///   label string.  Cache entries are removed in [dispose] for every label
///   that this painter instance owns, preventing unbounded growth.
///
/// ## Testing
///
/// Call [clearCacheForTesting] in `tearDown` to reset the static cache between
/// test groups so cached [TextPainter] state does not cross-contaminate tests.
class BoundingBoxPainter extends CustomPainter {
  BoundingBoxPainter({
    required this.boxes,
    this.mirrorHorizontal = false,
    this.version = 0,
  });

  final List<SmoothedBox> boxes;
  final bool mirrorHorizontal;
  final int version;

  // ── Static TextPainter cache ─────────────────────────────────────────────

  static final Map<String, TextPainter> _textCache = {};

  /// Removes cache entries for all labels owned by this painter.
  /// Call in [CustomPainter.dispose] (wired via [WidgetState.dispose]).
  void dispose() {
    for (final box in boxes) {
      _textCache.remove(box.label);
    }
  }

  /// Clears the entire static cache.  Call in `tearDown` inside unit / widget
  /// tests to avoid state leakage between test groups.
  static void clearCacheForTesting() => _textCache.clear();

  // ── CustomPainter ─────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(BoundingBoxPainter oldDelegate) =>
      version != oldDelegate.version ||
      mirrorHorizontal != oldDelegate.mirrorHorizontal ||
      (version == 0 &&
          oldDelegate.version == 0 &&
          !_sameBoxes(oldDelegate.boxes));

  bool _sameBoxes(List<SmoothedBox> otherBoxes) {
    if (identical(boxes, otherBoxes)) return true;
    if (boxes.length != otherBoxes.length) return false;

    for (var i = 0; i < boxes.length; i++) {
      final current = boxes[i];
      final other = otherBoxes[i];
      if (current.left != other.left ||
          current.top != other.top ||
          current.width != other.width ||
          current.height != other.height ||
          current.label != other.label ||
          current.trackId != other.trackId ||
          current.missedFrames != other.missedFrames) {
        return false;
      }
    }

    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (boxes.isEmpty) return;

    // Guard against a zero-sized canvas (e.g. before layout completes).
    if (size.width <= 0 || size.height <= 0) return;

    if (mirrorHorizontal) {
      canvas.save();
      canvas.scale(-1, 1);
      canvas.translate(-size.width, 0);
    }

    for (final box in boxes) {
      _paintBox(canvas, size, box);
    }

    if (mirrorHorizontal) canvas.restore();
  }

  // ── Per-box rendering ─────────────────────────────────────────────────────

  void _paintBox(Canvas canvas, Size size, SmoothedBox box) {
    // Clamp to visible area — prevents out-of-bounds boxes from crashing.
    final left = (box.left.clamp(0.0, 1.0) * size.width);
    final top = (box.top.clamp(0.0, 1.0) * size.height);
    final right = ((box.left + box.width).clamp(0.0, 1.0) * size.width);
    final bottom = ((box.top + box.height).clamp(0.0, 1.0) * size.height);

    final rectW = right - left;
    final rectH = bottom - top;

    // Skip boxes that are too small or have extreme aspect ratios.
    final area = (rectW / size.width) * (rectH / size.height);
    if (area < AppConstants.minRenderableBoxArea) return;
    final aspectRatio = rectW > 0 && rectH > 0
        ? (rectW > rectH ? rectW / rectH : rectH / rectW)
        : double.infinity;
    if (aspectRatio > AppConstants.maxRenderableAspectRatio) return;

    final rect = Rect.fromLTRB(left, top, right, bottom);

    // Per-box opacity fades out as missedFrames grows.
    final opacity = (1.0 - box.missedFrames * 0.3).clamp(0.2, 1.0);
    final color = _colorForLabel(box.label).withValues(alpha: opacity);

    // ── Border ──────────────────────────────────────────────────────────────
    final borderPaint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, borderPaint);

    // ── Corner accents ───────────────────────────────────────────────────────
    const cornerLen = 16.0;
    _drawCorner(canvas, borderPaint, rect, cornerLen);

    // ── Label badge ──────────────────────────────────────────────────────────
    final tp = _getOrCreateTextPainter(box.label, color, opacity);
    final labelW = tp.width + 12;
    final labelH = tp.height + 6;
    final badgeRect = Rect.fromLTWH(left, top - labelH, labelW, labelH);

    canvas.drawRect(
      badgeRect,
      Paint()
        ..color = color.withValues(alpha: (opacity * 0.85).clamp(0.0, 1.0)),
    );

    tp.paint(canvas, Offset(left + 6, top - labelH + 3));
  }

  // ── Corner accent helper ──────────────────────────────────────────────────

  void _drawCorner(Canvas canvas, Paint paint, Rect r, double len) {
    // Top-left
    canvas.drawLine(r.topLeft, r.topLeft.translate(len, 0), paint);
    canvas.drawLine(r.topLeft, r.topLeft.translate(0, len), paint);
    // Top-right
    canvas.drawLine(r.topRight, r.topRight.translate(-len, 0), paint);
    canvas.drawLine(r.topRight, r.topRight.translate(0, len), paint);
    // Bottom-left
    canvas.drawLine(r.bottomLeft, r.bottomLeft.translate(len, 0), paint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft.translate(0, -len), paint);
    // Bottom-right
    canvas.drawLine(r.bottomRight, r.bottomRight.translate(-len, 0), paint);
    canvas.drawLine(r.bottomRight, r.bottomRight.translate(0, -len), paint);
  }

  // ── TextPainter cache ─────────────────────────────────────────────────────

  TextPainter _getOrCreateTextPainter(
    String label,
    Color color,
    double opacity,
  ) {
    // Cache by label only; color / opacity are set on the existing painter
    // each call so we do not proliferate cache entries per opacity value.
    if (!_textCache.containsKey(label)) {
      final tp = TextPainter(textDirection: TextDirection.ltr);
      _textCache[label] = tp;
    }

    final tp = _textCache[label]!;
    tp.text = TextSpan(
      text: VoiceHelper.normalizeLabel(label),
      style: TextStyle(
        color: Colors.white.withValues(alpha: opacity.clamp(0.2, 1.0)),
        fontSize: 13,
        fontWeight: FontWeight.bold,
        shadows: const [
          Shadow(blurRadius: 2, color: Colors.black),
        ],
      ),
    );
    tp.layout(maxWidth: 200);
    return tp;
  }

  // ── Deterministic label colour ────────────────────────────────────────────

  static const List<Color> _palette = [
    Color(0xFF00E5FF), // cyan
    Color(0xFF69FF47), // lime
    Color(0xFFFF6D00), // deep orange
    Color(0xFFE040FB), // purple
    Color(0xFFFFD740), // amber
    Color(0xFF40C4FF), // light blue
    Color(0xFF69FFCC), // teal
    Color(0xFFFF4081), // pink
    Color(0xFFB2FF59), // light green
    Color(0xFFFFAB40), // orange
    Color(0xFF80D8FF), // sky blue
    Color(0xFFEA80FC), // light purple
    Color(0xFFCCFF90), // light lime
  ];

  static Color _colorForLabel(String label) =>
      _palette[label.hashCode.abs() % _palette.length];
}
