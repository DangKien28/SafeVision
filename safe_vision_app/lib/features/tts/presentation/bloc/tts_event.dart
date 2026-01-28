abstract class TtsEvent {}

class SpeakRequested extends TtsEvent {
  final String text;
  SpeakRequested(this.text);
}

class StopRequested extends TtsEvent {}