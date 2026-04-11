import 'package:equatable/equatable.dart';
import 'package:camera/camera.dart';

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
  final CameraImage image;
  final int rotationDegrees;
  final void Function() onDone;

  const DetectionFrameReceived(this.image, this.rotationDegrees, this.onDone);

  @override
  List<Object?> get props => [image, rotationDegrees];
}
