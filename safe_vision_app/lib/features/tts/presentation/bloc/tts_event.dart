import 'package:equatable/equatable.dart';
import '../../domain/entities/tts_playback_update.dart';

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

class TtsPlaybackReported extends TtsEvent {
  const TtsPlaybackReported(this.update);

  final TtsPlaybackUpdate update;

  @override
  List<Object?> get props => [update.status, update.text, update.message];
}
