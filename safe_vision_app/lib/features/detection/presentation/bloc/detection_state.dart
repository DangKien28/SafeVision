import 'package:equatable/equatable.dart';
import '../../domain/entities/detection_object.dart';

abstract class DetectionState extends Equatable {
  const DetectionState();
  @override
  List<Object?> get props => [];
}

class DetectionInitial extends DetectionState {
  const DetectionInitial();
}

class DetectionLoading extends DetectionState {
  const DetectionLoading();
}

class DetectionModelReady extends DetectionState {
  const DetectionModelReady();
}

class DetectionSuccess extends DetectionState {
  final List<DetectionObject> detections;
  final int timestamp;

  const DetectionSuccess({required this.detections, required this.timestamp});

  @override
  List<Object?> get props => [detections, timestamp];
}

class DetectionFailure extends DetectionState {
  final String message;
  const DetectionFailure(this.message);
  @override
  List<Object?> get props => [message];
}
