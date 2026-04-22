import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
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

  /// Create a SmoothedBox from a plain DetectionObject-like instance.
  factory SmoothedBox.fromDetectionObject(dynamic detection) {
    final box = detection.boundingBox;
    return SmoothedBox(
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      label: detection.label,
      trackId: -1,
      missedFrames: 0,
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

class ObjectIndicatorPainter extends CustomPainter {
  ObjectIndicatorPainter({
    required this.boxes,
    this.mirrorHorizontal = false,
    this.version = 0,
    this.animationValue = 0.0,
  });

  final List<SmoothedBox> boxes;
  final bool mirrorHorizontal;
  final int version;
  final double animationValue;

  static final Map<String, Object?> _textCache = {};
  final Set<String> _instanceCachedKeys = <String>{};

  static void clearCache() => _textCache.clear();
  static void clearCacheForTesting() => clearCache();

  void dispose() {
    for (final key in _instanceCachedKeys) {
      _textCache.remove(key);
    }
    _instanceCachedKeys.clear();
  }

  @override
  bool shouldRepaint(ObjectIndicatorPainter oldDelegate) =>
      version != oldDelegate.version ||
      mirrorHorizontal != oldDelegate.mirrorHorizontal ||
      animationValue != oldDelegate.animationValue ||
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

    final points = boxes
        .map((b) => _toRenderable(size, b))
        .whereType<_RenderablePoint>()
        .toList(growable: false);
    if (points.isEmpty) return;

    _paintEdgeIndicators(canvas, size, points);
    _paintCentroids(canvas, size, points);
  }

  _RenderablePoint? _toRenderable(Size size, SmoothedBox box) {
    final clampedLeft = box.left.clamp(0.0, 1.0);
    final clampedTop = box.top.clamp(0.0, 1.0);
    final clampedRight = (box.left + box.width).clamp(0.0, 1.0);
    final clampedBottom = (box.top + box.height).clamp(0.0, 1.0);

    final normalizedWidth = clampedRight - clampedLeft;
    final normalizedHeight = clampedBottom - clampedTop;
    if (normalizedWidth <= 0 || normalizedHeight <= 0) return null;

    final area = normalizedWidth * normalizedHeight;
    if (area < AppConstants.minRenderableBoxArea) return null;

    final aspectRatio = normalizedWidth > normalizedHeight
        ? normalizedWidth / normalizedHeight
        : normalizedHeight / normalizedWidth;
    if (aspectRatio > AppConstants.maxRenderableAspectRatio) return null;

    final centerX = (clampedLeft + clampedRight) / 2;
    final centerY = (clampedTop + clampedBottom) / 2;

    final displayCenterX = mirrorHorizontal ? (1.0 - centerX) : centerX;
    final px = displayCenterX * size.width;
    final py = centerY * size.height;
    final opacity = (1.0 - box.missedFrames * 0.3).clamp(0.2, 1.0);
    final isDangerous = area >= AppConstants.dangerousAreaThreshold;

    return _RenderablePoint(
      center: Offset(px, py),
      normalizedArea: area,
      opacity: opacity,
      isDangerous: isDangerous,
      zone: _zoneForCenter(centerX),
    );
  }

  _EdgeZone _zoneForCenter(double centerX) {
    if (centerX < 0.33) return _EdgeZone.left;
    if (centerX > 0.67) return _EdgeZone.right;
    return _EdgeZone.center;
  }

  void _paintEdgeIndicators(
    Canvas canvas,
    Size size,
    List<_RenderablePoint> points,
  ) {
    double leftIntensity = 0;
    double centerIntensity = 0;
    double rightIntensity = 0;
    bool leftDanger = false;
    bool centerDanger = false;
    bool rightDanger = false;

    for (final point in points) {
      switch (point.zone) {
        case _EdgeZone.left:
          leftIntensity = math.max(leftIntensity, point.opacity);
          leftDanger = leftDanger || point.isDangerous;
        case _EdgeZone.center:
          centerIntensity = math.max(centerIntensity, point.opacity);
          centerDanger = centerDanger || point.isDangerous;
        case _EdgeZone.right:
          rightIntensity = math.max(rightIntensity, point.opacity);
          rightDanger = rightDanger || point.isDangerous;
      }
    }

    final radius = size.shortestSide * 0.22;
    final strokeWidth = math.max(8.0, size.shortestSide * 0.03);

    if (leftIntensity > 0) {
      final color =
          _indicatorColor(leftDanger).withValues(alpha: leftIntensity);
      _paintArc(
        canvas: canvas,
        rect:
            Rect.fromCircle(center: Offset(0, size.height / 2), radius: radius),
        startAngle: -math.pi / 2,
        sweepAngle: math.pi,
        color: color,
        strokeWidth: strokeWidth,
      );
    }
    if (centerIntensity > 0) {
      final color =
          _indicatorColor(centerDanger).withValues(alpha: centerIntensity);
      _paintArc(
        canvas: canvas,
        rect:
            Rect.fromCircle(center: Offset(size.width / 2, 0), radius: radius),
        startAngle: math.pi,
        sweepAngle: math.pi,
        color: color,
        strokeWidth: strokeWidth,
      );
    }
    if (rightIntensity > 0) {
      final color =
          _indicatorColor(rightDanger).withValues(alpha: rightIntensity);
      _paintArc(
        canvas: canvas,
        rect: Rect.fromCircle(
            center: Offset(size.width, size.height / 2), radius: radius),
        startAngle: math.pi / 2,
        sweepAngle: math.pi,
        color: color,
        strokeWidth: strokeWidth,
      );
    }
  }

  void _paintArc({
    required Canvas canvas,
    required Rect rect,
    required double startAngle,
    required double sweepAngle,
    required Color color,
    required double strokeWidth,
  }) {
    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth,
    );
  }

  void _paintCentroids(
    Canvas canvas,
    Size size,
    List<_RenderablePoint> points,
  ) {
    for (final point in points) {
      final color =
          _indicatorColor(point.isDangerous).withValues(alpha: point.opacity);
      final normalizedArea = point.normalizedArea.clamp(0.0, 1.0);

      final baseRadius = math.max(
        6.0,
        size.shortestSide * (0.01 + normalizedArea * 0.08),
      );
      final pulseExpansion = 1.0 + animationValue * 1.8;
      final pulseOpacity =
          ((1.0 - animationValue) * point.opacity * 0.8).clamp(0.0, 1.0);

      canvas.drawCircle(
        point.center,
        baseRadius,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color,
      );

      canvas.drawCircle(
        point.center,
        baseRadius * pulseExpansion,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, baseRadius * 0.25)
          ..color = color.withValues(alpha: pulseOpacity),
      );
    }
  }

  Color _indicatorColor(bool isDangerous) =>
      isDangerous ? AppColors.warning : AppColors.primary;

  
}

class _RenderablePoint {
  const _RenderablePoint({
    required this.center,
    required this.normalizedArea,
    required this.opacity,
    required this.isDangerous,
    required this.zone,
  });

  final Offset center;
  final double normalizedArea;
  final double opacity;
  final bool isDangerous;
  final _EdgeZone zone;
}

enum _EdgeZone {
  left,
  center,
  right,
}
