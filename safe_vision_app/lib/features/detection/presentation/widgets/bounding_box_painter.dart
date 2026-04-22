import 'dart:collection';

import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/detection_object.dart';

/// Position and state for an object after tracker smoothing.
/// [missedFrames] is used to gradually reduce opacity when the object
/// temporarily disappears.
class SmoothedBox {
  final double left, top, width, height;
  final String label;
  final int trackId;
  final int missedFrames;

  const SmoothedBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.label,
    required this.trackId,
    required this.missedFrames,
  });

  @override
  bool operator ==(Object other) =>
      other is SmoothedBox &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height &&
      label == other.label &&
      trackId == other.trackId &&
      missedFrames == other.missedFrames;

  @override
  int get hashCode =>
      Object.hash(left, top, width, height, label, trackId, missedFrames);
}

/// Internal state for a track, storing the smoothed position and the
/// last time the object was seen.
class _TrackedBox {
  static const double alpha = AppConstants.trackingSmoothingAlpha;
  final int trackId;
  double left, top, width, height;
  final String label;
  DateTime lastSeenAt;
  int missedFrames;

  _TrackedBox({
    required this.trackId,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.label,
    required this.lastSeenAt,
  }) : missedFrames = 0;

  /// Applies exponential smoothing so bounding boxes move smoothly instead of
  /// jumping abruptly between frames.
  void update(BoundingBox box, DateTime now) {
    left = left * (1 - alpha) + box.left * alpha;
    top = top * (1 - alpha) + box.top * alpha;
    width = width * (1 - alpha) + box.width * alpha;
    height = height * (1 - alpha) + box.height * alpha;
    missedFrames = 0;
    lastSeenAt = now;
  }

  SmoothedBox snapshot() => SmoothedBox(
        left: left,
        top: top,
        width: width,
        height: height,
        label: label,
        trackId: trackId,
        missedFrames: missedFrames,
      );
}

/// Manages [_TrackedBox] instances across consecutive frames.
/// Uses IoU to match new detections to existing tracks with greedy matching.
/// Tracks are removed after [maxTrackAge] if no detection matches them.
///
/// [version] increments whenever state changes and is used by
/// [BoundingBoxPainter.shouldRepaint] for an `O(1)` comparison.
class BoxTracker {
  final Map<int, _TrackedBox> _tracked = {};
  int _nextTrackId = 0;

  int _version = 0;
  int get version => _version;

  static const double matchThreshold = 0.35;
  static const Duration maxTrackAge =
      Duration(milliseconds: AppConstants.trackingMaxAgeMs);

  List<SmoothedBox> update(List<DetectionObject> detections, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();

    for (final tracked in _tracked.values) {
      tracked.missedFrames++;
    }

    final usedTrackIds = <int>{};
    for (final det in detections) {
      final box = det.boundingBox;
      int? bestTrackId;
      double bestIou = 0;

      for (final entry in _tracked.entries) {
        final tracked = entry.value;
        if (tracked.label != det.label) continue;
        if (usedTrackIds.contains(entry.key)) continue;
        final iou = _iou(tracked.left, tracked.top, tracked.width,
            tracked.height, box.left, box.top, box.width, box.height);
        if (iou > bestIou) {
          bestIou = iou;
          bestTrackId = entry.key;
        }
      }

      if (bestTrackId != null && bestIou > matchThreshold) {
        _tracked[bestTrackId]!.update(box, timestamp);
        usedTrackIds.add(bestTrackId);
      } else {
        final trackId = _nextTrackId++;
        _tracked[trackId] = _TrackedBox(
          trackId: trackId,
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
          label: det.label,
          lastSeenAt: timestamp,
        );
        usedTrackIds.add(trackId);
      }
    }

    _tracked.removeWhere(
      (_, tracked) => timestamp.difference(tracked.lastSeenAt) > maxTrackAge,
    );

    _version++;
    return _tracked.values.map((t) => t.snapshot()).toList(growable: false)
      ..sort((a, b) => a.trackId.compareTo(b.trackId));
  }

  double _iou(double al, double at, double aw, double ah, double bl, double bt,
      double bw, double bh) {
    final iL = al > bl ? al : bl;
    final iT = at > bt ? at : bt;
    final iR = (al + aw) < (bl + bw) ? (al + aw) : (bl + bw);
    final iB = (at + ah) < (bt + bh) ? (at + ah) : (bt + bh);
    if (iR <= iL || iB <= iT) return 0;
    final inter = (iR - iL) * (iB - iT);
    return inter / (aw * ah + bw * bh - inter);
  }

  void clear() {
    _tracked.clear();
    _nextTrackId = 0;
    _version++;
  }
}

/// Draws [SmoothedBox] bounding boxes onto the camera canvas.
///
/// [version] enables an `O(1)` comparison inside [shouldRepaint] instead of
/// walking every box on each frame.
///
/// [TextPainter] instances are cached by label to avoid repeated text layout.
/// The cache uses LRU eviction via [LinkedHashMap]: entries are promoted to
/// the tail on access and evicted from the head when full.
///
/// The cache manages its own lifecycle. Instance [dispose] is intentionally a
/// no-op for the static cache — eviction handles cleanup. This avoids a
/// use-after-free trap when two painter instances briefly coexist during a
/// [ValueListenableBuilder] rebuild.
class BoundingBoxPainter extends CustomPainter {
  final List<SmoothedBox> boxes;
  final bool mirrorHorizontal;
  final int _version;

  /// LRU [TextPainter] cache: head = oldest (eviction target), tail = newest.
  /// Uses [LinkedHashMap] insertion-order semantics for O(1) promotion.
  static final LinkedHashMap<String, TextPainter> _textCache =
      LinkedHashMap<String, TextPainter>();
  static const int _maxCacheEntries = 50;

  /// Paint objects stay as final instance fields instead of static fields to
  /// avoid shared mutable state between painter instances.
  /// Each frame gets its own small set of Paint objects, which is safer.
  final Paint _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  final Paint _cornerPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.0;

  final Paint _labelPaint = Paint()..style = PaintingStyle.fill;

  BoundingBoxPainter({
    required this.boxes,
    this.mirrorHorizontal = false,
    int version = 0,
  }) : _version = version;

  /// No-op for instance disposal.
  ///
  /// [CustomPainter] has no framework-managed `dispose()` lifecycle, so this
  /// method is never called automatically. The static [_textCache] manages its
  /// own lifecycle through LRU eviction. Removing entries here would cause a
  /// use-after-free if two painter instances briefly coexist during a rebuild.
  void dispose() {
    // Intentionally empty — LRU eviction handles cache cleanup.
  }

  /// Clears the entire [TextPainter] cache and disposes every entry.
  /// Intended for test tearDown logic to reset static state between tests and
  /// avoid cross-test pollution.
  // ignore: invalid_use_of_visible_for_testing_member
  static void clearCacheForTesting() {
    for (final tp in _textCache.values) {
      tp.dispose();
    }
    _textCache.clear();
  }

  /// Returns true only when the version counter or mirror flag changes.
  /// This stays `O(1)` and does not iterate through the boxes list.
  @override
  bool shouldRepaint(covariant BoundingBoxPainter old) {
    if (mirrorHorizontal != old.mirrorHorizontal) return true;
    if (_version != old._version) return true;
    // Fallback when versioning is not provided (`version == 0` on both sides).
    if (_version == 0 && old._version == 0) {
      if (boxes.length != old.boxes.length) return true;
      for (int i = 0; i < boxes.length; i++) {
        if (boxes[i] != old.boxes[i]) return true;
      }
    }
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      _drawBox(canvas, size, box);
    }
  }

  void _drawBox(Canvas canvas, Size size, SmoothedBox box) {
    double l = box.left * size.width;
    double t = box.top * size.height;
    double r = (box.left + box.width) * size.width;
    double b = (box.top + box.height) * size.height;

    if (mirrorHorizontal) {
      final tmp = l;
      l = size.width - r;
      r = size.width - tmp;
    }

    l = l.clamp(0, size.width);
    t = t.clamp(0, size.height);
    r = r.clamp(0, size.width);
    b = b.clamp(0, size.height);
    if (r - l < 2 || b - t < 2) return;

    final rect = Rect.fromLTRB(l, t, r, b);
    final color = _colorForLabel(box.label);

    // Reduce opacity as missed frames increase to create a fade-out effect.
    final opacity = box.missedFrames == 0
        ? 1.0
        : (1.0 - box.missedFrames / 4.0).clamp(0.2, 1.0);

    _strokePaint.color = color.withValues(alpha: 0.85 * opacity);
    _cornerPaint.color = color.withValues(alpha: opacity);
    _labelPaint.color = color.withValues(alpha: 0.9);

    canvas.drawRect(rect, _strokePaint);
    _drawCorners(canvas, rect, _cornerPaint);
    _drawLabel(canvas, size, rect, box.label, _labelPaint);
  }

  /// Draws emphasized corners to keep the box visible on busy backgrounds.
  void _drawCorners(Canvas canvas, Rect rect, Paint paint) {
    final len = (rect.width * 0.15).clamp(8.0, 20.0);
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + len)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.left + len, rect.top)
        ..moveTo(rect.right - len, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.top + len)
        ..moveTo(rect.left, rect.bottom - len)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.left + len, rect.bottom)
        ..moveTo(rect.right - len, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.right, rect.bottom - len),
      paint,
    );
  }

  void _drawLabel(
      Canvas canvas, Size size, Rect rect, String label, Paint bgPaint) {
    final tp = _getOrCreatePainter(label);
    final lw = tp.width + 10;
    final lh = tp.height + 5;
    final lt = (rect.top - lh - 2).clamp(0.0, size.height - lh);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, lt, lw, lh),
        const Radius.circular(3),
      ),
      bgPaint,
    );
    tp.paint(canvas, Offset(rect.left + 5, lt + 2.5));
  }

  /// Returns a cached [TextPainter] or creates a new one.
  ///
  /// On cache hit, the entry is promoted to the tail (most recently used).
  /// On cache miss at capacity, the head (least recently used) is evicted.
  TextPainter _getOrCreatePainter(String label) {
    if (_textCache.containsKey(label)) {
      // Promote to MRU position: remove and reinsert at tail.
      final tp = _textCache.remove(label)!;
      _textCache[label] = tp;
      return tp;
    }

    // Evict LRU entry (head of LinkedHashMap) when at capacity.
    if (_textCache.length >= _maxCacheEntries) {
      final lruKey = _textCache.keys.first;
      _textCache.remove(lruKey)!.dispose();
    }

    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 200);

    _textCache[label] = painter;
    return painter;
  }

  /// Assigns a stable color to each label based on its hash so the color stays
  /// consistent across frames and across tracks of the same class.
  Color _colorForLabel(String label) {
    const palette = [
      Color(0xFF00E676),
      Color(0xFF00B0FF),
      Color(0xFFFF6D00),
      Color(0xFFD500F9),
      Color(0xFF00E5FF),
      Color(0xFFFF4081),
    ];
    return palette[label.hashCode.abs() % palette.length];
  }
}
