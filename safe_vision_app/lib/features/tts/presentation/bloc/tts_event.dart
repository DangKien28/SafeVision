import 'package:equatable/equatable.dart';

abstract class TtsEvent extends Equatable {
  const TtsEvent();
  @override
  List<Object?> get props => [];
}

class TtsSpeak extends TtsEvent {
  final String text;
  final bool immediate;
  final bool withVibration;

  const TtsSpeak(
    this.text, {
    this.immediate = false,
    this.withVibration = false,
  });

  @override
  List<Object?> get props => [text, immediate, withVibration];
}

class TtsStop extends TtsEvent {
  const TtsStop();
}

class TtsPause extends TtsEvent {
  const TtsPause();
}
