import '../../domain/entities/bounding_box_entity.dart';

abstract class DetectionState {}

class DetectionInitial extends DetectionState {}

class DetectionLoading extends DetectionState {}

class DetectionLoaded extends DetectionState {
  final List<BoundingBoxEntity> boxes;
  DetectionLoaded(this.boxes);
}

class DetectionError extends DetectionState {
  final String message;
  DetectionError(this.message);
}
