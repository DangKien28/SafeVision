import 'package:equatable/equatable.dart';
import 'package:camera/camera.dart';

abstract class DetectionEvent extends Equatable {
  const DetectionEvent();
  @override List<Object?> get props => [];
}

class DetectionStarted    extends DetectionEvent { const DetectionStarted(); }
class DetectionStopped    extends DetectionEvent { const DetectionStopped(); }
class DetectionModelLoaded extends DetectionEvent { const DetectionModelLoaded(); }

class DetectionFrameReceived extends DetectionEvent {
  final CameraImage image;
  const DetectionFrameReceived(this.image);
  @override List<Object?> get props => [image];
}