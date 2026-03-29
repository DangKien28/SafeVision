import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vibration/vibration.dart';
import '../../domain/usecases/speak_warning_usecase.dart';
import '../../domain/usecases/stop_speaking_usecase.dart';
import 'tts_event.dart';
import 'tts_state.dart';

class TtsBloc extends Bloc<TtsEvent, TtsState> {
  final SpeakWarningUsecase _speakWarning;
  final StopSpeakingUsecase _stopSpeaking;

  TtsBloc({
    required SpeakWarningUsecase speakWarning,
    required StopSpeakingUsecase stopSpeaking,
  })  : _speakWarning = speakWarning,
        _stopSpeaking = stopSpeaking,
        super(const TtsInitial()) {
    on<TtsSpeak>(_onSpeak);
    on<TtsStop>(_onStop);
    on<TtsPause>(_onPause);
  }

  Future<void> _onSpeak(TtsSpeak event, Emitter<TtsState> emit) async {
    try {
      // Rung nếu được yêu cầu
      if (event.withVibration) {
        final hasVibrator = await Vibration.hasVibrator() ?? false;
        if (hasVibrator) {
          Vibration.vibrate(pattern: [0, 300, 150, 300]);
        }
      }

      if (event.immediate) {
        await _speakWarning.immediate(event.text);
      } else {
        await _speakWarning(event.text);
      }

      emit(TtsSpeaking(event.text));
    } catch (e) {
      emit(TtsError(e.toString()));
    }
  }

  Future<void> _onStop(TtsStop event, Emitter<TtsState> emit) async {
    await _stopSpeaking();
    emit(const TtsStopped());
  }

  Future<void> _onPause(TtsPause event, Emitter<TtsState> emit) async {
    emit(const TtsPaused());
  }
}