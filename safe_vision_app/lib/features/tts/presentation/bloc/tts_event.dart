import 'package:equatable/equatable.dart';

abstract class TtsEvent extends Equatable {
  const TtsEvent();

  @override
  List<Object?> get props => [];
}

class TtsSpeak extends TtsEvent {
  const TtsSpeak(
    this.text, {
    this.immediate = false,
    this.withVibration = false,
  });

  final String text;
  final bool immediate;
  final bool withVibration;

  @override
  List<Object?> get props => [text, immediate, withVibration];
}

class TtsStop extends TtsEvent {
  const TtsStop();
}

class TtsPause extends TtsEvent {
  const TtsPause();
}
