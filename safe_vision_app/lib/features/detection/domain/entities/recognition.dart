import 'package:equatable/equatable.dart';
import 'detection_object.dart';

/// Legacy wrapper kept for backward compatibility with the UI layer.
/// Prefer [DetectionObject] for new code.
class Recognition extends Equatable {
  const Recognition({
    required this.id,
    required this.label,
    required this.score,
    required this.location,
  });

  final int id;
  final String label;
  final double score;
  final BoundingBox location;

  DetectionObject toDetectionObject() => DetectionObject(
        label: label,
        confidence: score,
        boundingBox: location,
      );

  @override
  List<Object?> get props => [id, label, score, location];
}
