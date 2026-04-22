import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vibration/vibration.dart';

import '../../../settings/domain/repositories/settings_repository.dart';
import '../../domain/usecases/speak_warning_usecase.dart';
import '../../domain/usecases/stop_speaking_usecase.dart';
import '../../domain/usecases/pause_speaking_usecase.dart';
import 'tts_event.dart';
import 'tts_state.dart';

/// Manages TTS state and bridges [DetectionBloc] events to
/// [SpeakWarningUsecase].
///
/// Before processing each [TtsSpeak], the BLoC checks
/// [SettingsRepository.getVoiceEnabled] so user preferences are respected
/// without needing to restart the BLoC.
///
/// Vibration ([Vibration.vibrate]) is triggered only if TTS is actually
/// accepted after the cooldown check, not on every incoming event.
class TtsBloc extends Bloc<TtsEvent, TtsState> {
  final SpeakWarningUsecase _speakWarning;
  final StopSpeakingUsecase _stopSpeaking;
  final PauseSpeakingUsecase _pauseSpeaking;
  final SettingsRepository _settingsRepository;

  TtsBloc({
    required SpeakWarningUsecase speakWarning,
    required StopSpeakingUsecase stopSpeaking,
    required PauseSpeakingUsecase pauseSpeaking,
    required SettingsRepository settingsRepository,
  })  : _speakWarning = speakWarning,
        _stopSpeaking = stopSpeaking,
        _pauseSpeaking = pauseSpeaking,
        _settingsRepository = settingsRepository,
        super(const TtsInitial()) {
    on<TtsSpeak>(_onSpeak);
    on<TtsStop>(_onStop);
    on<TtsPause>(_onPause);
  }

  Future<void> _onSpeak(TtsSpeak event, Emitter<TtsState> emit) async {
    try {
      final voiceEnabled = await _settingsRepository.getVoiceEnabled();
      if (!voiceEnabled) {
        // Stop any active audio regardless of current BLoC state.
        // The engine may be speaking even if state is not TtsSpeaking
        // (e.g. after an error recovery).
        await _stopSpeaking();
        if (state is! TtsStopped) emit(const TtsStopped());
        return;
      }

      final bool accepted = event.immediate
          ? await _speakWarning.immediate(event.text)
          : await _speakWarning(event.text);

      if (accepted && event.withVibration) {
        final bool hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          Vibration.vibrate(pattern: [0, 300, 150, 300]);
        }
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
    await _pauseSpeaking();
    emit(const TtsPaused());
  }
}
