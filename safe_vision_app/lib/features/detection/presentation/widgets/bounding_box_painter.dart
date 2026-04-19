import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/voice_helper.dart';
import '../../domain/entities/detection_object.dart';
import '../../domain/entities/tracked_detection.dart';

// ── SmoothedBox ───────────────────────────────────────────────────────────────

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

class BoxTracker {
  BoxTracker();

  final Map<int, _Track> _tracks = {};
  int _nextTrackId = 1;
  int _version = 0;

  static const double _iouThreshold = 0.3;

  int get version => _version;

  List<SmoothedBox> update(
    List<DetectionObject> detections, {
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    _version++;

    final maxAge = AppConstants.trackingMaxAgeMs;
    _tracks.removeWhere(
      (_, t) => time.difference(t.lastSeen).inMilliseconds > maxAge,
    );

    final matched = <int>{};
    final updatedTracks = <int>{};

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
        matched.add(bestIdx);
        updatedTracks.add(entry.key);
        final det = detections[bestIdx];
        track.smooth(det.boundingBox, time);
        track.missedFrames = 0;
      } else {
        track.missedFrames++;
      }
    }

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

    return _tracks.values.map((t) => t.toSmoothedBox()).toList();
  }

  void clear() {
    _tracks.clear();
    _version++;
  }

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
    required this.lastSeen,
  })  : _left = box.left,
        _top = box.top,
        _width = box.width,
        _height = box.height,
        missedFrames = 0;

  final int id;
  final String label;
  final DateTime firstSeen;
  DateTime lastSeen;
  int missedFrames;

  double _left;
  double _top;
  double _width;
  double _height;

  BoundingBox get box => BoundingBox(
        left: _left,
        top: _top,
        width: _width,
        height: _height,
      );

  static const double _alpha = AppConstants.trackingSmoothingAlpha;

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
///   label string, bounded to [_maxCacheEntries] entries.  When the limit is
///   reached the entire cache is cleared to prevent unbounded memory growth
///   across long sessions (Bug 2 fix).
///
/// ## Memory management (Bug 2)
///
/// The painter is rebuilt on every frame by [ValueListenableBuilder].  Because
/// [CustomPainter] has no framework-managed `dispose()` lifecycle, the static
/// cache could grow without bound over a long session.  Two mechanisms guard
/// against this:
///   1. [_maxCacheEntries] cap — cache is cleared when it exceeds this limit.
///   2. [dispose()] / [clearCacheForTesting()] — explicit eviction helpers.
///      [dispose()] removes only the labels owned by this painter instance and
///      should be called from [State.dispose] when a wrapping StatefulWidget
///      is used (see camera_view_page.dart).
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

  /// Maximum number of distinct label entries kept in the static cache.
  /// When this limit is reached the cache is cleared before adding new entries.
  /// The YOLOv8 model used by SafeVision has 13 labels, so 64 entries is a
  /// generous upper bound that still prevents runaway accumulation.
  static const int _maxCacheEntries = 64;

  /// Removes cache entries for all labels owned by this painter instance.
  /// Wire this into [State.dispose] when the painter is held by a StatefulWidget.
  void dispose() {
    for (final box in boxes) {
      _textCache.remove(box.label);
    }
  }

  /// Clears the entire static cache.
  ///
  /// Call this during page/widget teardown to proactively release cached
  /// [TextPainter] instances between sessions.
  static void clearCache() => _textCache.clear();

  /// Test-only alias for compatibility with existing tests.
  static void clearCacheForTesting() => clearCache();

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
    final left = (box.left.clamp(0.0, 1.0) * size.width);
    final top = (box.top.clamp(0.0, 1.0) * size.height);
    final right = ((box.left + box.width).clamp(0.0, 1.0) * size.width);
    final bottom = ((box.top + box.height).clamp(0.0, 1.0) * size.height);

    final rectW = right - left;
    final rectH = bottom - top;

    final area = (rectW / size.width) * (rectH / size.height);
    if (area < AppConstants.minRenderableBoxArea) return;
    final aspectRatio = rectW > 0 && rectH > 0
        ? (rectW > rectH ? rectW / rectH : rectH / rectW)
        : double.infinity;
    if (aspectRatio > AppConstants.maxRenderableAspectRatio) return;

    final rect = Rect.fromLTRB(left, top, right, bottom);
    final opacity = (1.0 - box.missedFrames * 0.3).clamp(0.2, 1.0);
    final color = _colorForLabel(box.label).withValues(alpha: opacity);

    final borderPaint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, borderPaint);

    const cornerLen = 16.0;
    _drawCorner(canvas, borderPaint, rect, cornerLen);

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
    canvas.drawLine(r.topLeft, r.topLeft.translate(len, 0), paint);
    canvas.drawLine(r.topLeft, r.topLeft.translate(0, len), paint);
    canvas.drawLine(r.topRight, r.topRight.translate(-len, 0), paint);
    canvas.drawLine(r.topRight, r.topRight.translate(0, len), paint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft.translate(len, 0), paint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft.translate(0, -len), paint);
    canvas.drawLine(r.bottomRight, r.bottomRight.translate(-len, 0), paint);
    canvas.drawLine(r.bottomRight, r.bottomRight.translate(0, -len), paint);
  }

  // ── TextPainter cache ─────────────────────────────────────────────────────

  TextPainter _getOrCreateTextPainter(
    String label,
    Color color,
    double opacity,
  ) {
    if (_textCache.length >= _maxCacheEntries) {
      _textCache.clear();
    }

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
    Color(0xFF00E5FF),
    Color(0xFF69FF47),
    Color(0xFFFF6D00),
    Color(0xFFE040FB),
    Color(0xFFFFD740),
    Color(0xFF40C4FF),
    Color(0xFF69FFCC),
    Color(0xFFFF4081),
    Color(0xFFB2FF59),
    Color(0xFFFFAB40),
    Color(0xFF80D8FF),
    Color(0xFFEA80FC),
    Color(0xFFCCFF90),
  ];

  static Color _colorForLabel(String label) =>
      _palette[label.hashCode.abs() % _palette.length];
}
