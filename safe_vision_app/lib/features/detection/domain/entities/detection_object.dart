import 'package:equatable/equatable.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/voice_helper.dart';

// ── BoundingBox ───────────────────────────────────────────────────────────────

/// Normalised bounding box in [0, 1] space relative to the camera preview.
class BoundingBox extends Equatable {
  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right  => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
  double get area   => width * height;

  /// Horizontal zone label for TTS position announcements.
  String get horizontalPosition {
    if (centerX < 0.33) return 'bên trái';
    if (centerX > 0.67) return 'bên phải';
    return 'phía trước';
  }

  /// Distance estimate based on bounding-box area.
  String get proximityLabel {
    if (area > 0.25) return 'rất gần';
    if (area > 0.10) return 'gần';
    if (area > 0.03) return 'khoảng cách trung bình';
    return 'xa';
  }

  @override
  List<Object?> get props => [left, top, width, height];
}

// ── DetectionObject ───────────────────────────────────────────────────────────

/// A single detected object produced by the inference pipeline.
class DetectionObject extends Equatable {
  const DetectionObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  final String label;
  final double confidence;
  final BoundingBox boundingBox;

  /// Full TTS warning sentence, e.g. "Cảnh báo! xe hơi ở bên trái, gần."
  String get voiceWarning => VoiceHelper.buildWarning(
        label: label,
        position: boundingBox.horizontalPosition,
        distance: boundingBox.proximityLabel,
      );

  /// True when the bounding-box area exceeds the danger threshold defined in
  /// [AppConstants.dangerousAreaThreshold].
  bool get isDangerous =>
      boundingBox.area > AppConstants.dangerousAreaThreshold;

  @override
  List<Object?> get props => [label, confidence, boundingBox];
}