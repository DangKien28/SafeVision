import 'package:equatable/equatable.dart';
import '../../../../core/models/camera_frame.dart';

abstract class DetectionEvent extends Equatable {
  const DetectionEvent();
  @override
  List<Object?> get props => [];
}

class DetectionStarted extends DetectionEvent {
  const DetectionStarted();
}

class DetectionStopped extends DetectionEvent {
  const DetectionStopped();
}

class DetectionFrameReceived extends DetectionEvent {
  final CameraFrame frame;
  final int rotationDegrees;
  final void Function() onDone;

  const DetectionFrameReceived(this.frame, this.rotationDegrees, this.onDone);

  @override
  List<Object?> get props => [frame, rotationDegrees];
}
