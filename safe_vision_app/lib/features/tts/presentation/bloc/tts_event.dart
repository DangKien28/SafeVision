import 'package:equatable/equatable.dart';

abstract class TtsEvent extends Equatable {
  const TtsEvent();
  @override List<Object?> get props => [];
}

class TtsSpeak extends TtsEvent {
  final String text;
  final bool immediate;
  final bool withVibration; // ← thêm field này

  const TtsSpeak(
    this.text, {
    this.immediate = false,
    this.withVibration = false, // ← default false
  });

  @override
  List<Object?> get props => [text, immediate, withVibration];
}

class TtsStop  extends TtsEvent { const TtsStop(); }
class TtsPause extends TtsEvent { const TtsPause(); }