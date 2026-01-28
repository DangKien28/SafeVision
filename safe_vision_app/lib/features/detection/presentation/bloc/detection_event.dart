abstract class DetectionEvent {}

class DetectFromFrameEvent extends DetectionEvent {
  final List<int> imageBytes;
  DetectFromFrameEvent(this.imageBytes);
}
