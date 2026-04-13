import '../../../../core/services/warning_dispatcher.dart';
import '../bloc/tts_bloc.dart';
import '../bloc/tts_event.dart';

/// Adapter that routes generic warning requests into the TTS presentation flow
/// without forcing detection code to depend directly on `TtsBloc`.
class TtsWarningDispatcher implements WarningDispatcher {
  TtsWarningDispatcher(this._readBloc);

  final TtsBloc Function() _readBloc;

  @override
  void dispatch({
    required String text,
    required bool immediate,
    required bool withVibration,
  }) {
    _readBloc().add(
      TtsSpeak(
        text,
        immediate: immediate,
        withVibration: withVibration,
      ),
    );
  }
}
