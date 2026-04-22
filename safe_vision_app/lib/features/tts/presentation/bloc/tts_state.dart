import 'package:equatable/equatable.dart';

abstract class TtsState extends Equatable {
  const TtsState();
  @override
  List<Object?> get props => [];
}

class TtsInitial extends TtsState {
  const TtsInitial();
}

class TtsSpeaking extends TtsState {
  final String text;
  const TtsSpeaking(this.text);
  @override
  List<Object?> get props => [text];
}

class TtsStopped extends TtsState {
  const TtsStopped();
}

class TtsPaused extends TtsState {
  const TtsPaused();
}

class TtsError extends TtsState {
  final String message;
  const TtsError(this.message);
  @override
  List<Object?> get props => [message];
}
