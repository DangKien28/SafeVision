import 'package:equatable/equatable.dart';
import 'detection_object.dart';

class Recognition extends Equatable {
  final int id;
  final String label;
  final double score;
  final BoundingBox location;

  const Recognition({
    required this.id,
    required this.label,
    required this.score,
    required this.location,
  });

  DetectionObject toDetectionObject() => DetectionObject(
        label: label,
        confidence: score,
        boundingBox: location,
      );

  @override
  List<Object?> get props => [id, label, score, location];
}