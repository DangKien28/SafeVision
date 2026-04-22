import 'package:equatable/equatable.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/voice_helper.dart';

/// Detection bounding box in normalized [0.0, 1.0] coordinates
/// relative to the camera frame size.
///
/// All derived properties such as `right`, `bottom`, and centers are computed
/// from the four base values, so no redundant state is stored.
class BoundingBox extends Equatable {
  final double left, top, width, height;

  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  /// Bounding-box area in normalized coordinates.
  /// Used as a distance proxy: the larger the area, the closer the object.
  double get area => width * height;

  /// Coarse horizontal position in three zones: left, center, and right.
  /// Thresholds `0.33` and `0.67` split the screen into equal thirds.
  String get horizontalPosition {
    if (centerX < 0.33) return 'bên trái';
    if (centerX > 0.67) return 'bên phải';
    return 'phía trước';
  }

  /// Distance label derived from the bounding-box area.
  /// Thresholds were chosen empirically for a typical phone camera.
  String get proximityLabel {
    if (area > 0.25) return 'rất gần';
    if (area > 0.10) return 'gần';
    if (area > 0.03) return 'khoảng cách trung bình';
    return 'xa';
  }

  @override
  List<Object?> get props => [left, top, width, height];
}

/// A single object detected from a camera frame, including class label,
/// confidence score, and bounding-box position.
///
/// [voiceWarning] returns a ready-to-speak warning sentence that includes
/// the label, horizontal position, and estimated distance.
///
/// [isDangerous] marks objects that require an immediate warning because the
/// bounding box occupies more than [AppConstants.dangerousAreaThreshold] of
/// the frame area.
class DetectionObject extends Equatable {
  final String label;
  final double confidence;
  final BoundingBox boundingBox;

  const DetectionObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  /// TTS warning sentence that combines label, position, and distance.
  String get voiceWarning => VoiceHelper.buildWarning(
        label: label,
        position: boundingBox.horizontalPosition,
        distance: boundingBox.proximityLabel,
      );

  /// Whether the object is large enough to count as an urgent hazard.
  /// Triggers immediate TTS and vibration feedback.
  bool get isDangerous =>
      boundingBox.area > AppConstants.dangerousAreaThreshold;

  @override
  List<Object?> get props => [label, confidence, boundingBox];
}
