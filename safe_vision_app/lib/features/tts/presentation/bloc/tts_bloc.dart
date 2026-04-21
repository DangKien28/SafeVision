import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vibration/vibration.dart';

import '../../../settings/domain/repositories/settings_repository.dart';
import '../../domain/entities/tts_playback_update.dart';
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
  final bool _usePlaybackUpdates;
  StreamSubscription<TtsPlaybackUpdate>? _playbackSubscription;

  TtsBloc({
    required SpeakWarningUsecase speakWarning,
    required StopSpeakingUsecase stopSpeaking,
    required PauseSpeakingUsecase pauseSpeaking,
    required SettingsRepository settingsRepository,
    Stream<TtsPlaybackUpdate>? playbackUpdates,
  })  : _speakWarning = speakWarning,
        _stopSpeaking = stopSpeaking,
        _pauseSpeaking = pauseSpeaking,
        _settingsRepository = settingsRepository,
        _usePlaybackUpdates = playbackUpdates != null,
        super(const TtsInitial()) {
    on<TtsSpeak>(_onSpeak);
    on<TtsStop>(_onStop);
    on<TtsPause>(_onPause);
    on<TtsPlaybackReported>(_onPlaybackReported);

    _playbackSubscription = playbackUpdates?.listen(
      (update) => add(TtsPlaybackReported(update)),
    );
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

      // Cooldown or queue dedupe can reject a request even when the pipeline is
      // healthy. In that case we keep the current state instead of claiming the
      // engine is speaking a sentence that was never accepted.
      if (!accepted) return;

      if (event.withVibration) {
        final bool hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          Vibration.vibrate(pattern: [0, 300, 150, 300]);
        }
      }

      if (!_usePlaybackUpdates) {
        emit(TtsSpeaking(event.text));
      }
    } catch (e) {
      emit(TtsError(e.toString()));
    }
  }

  Future<void> _onStop(TtsStop event, Emitter<TtsState> emit) async {
    await _stopSpeaking();
    if (!_usePlaybackUpdates) {
      emit(const TtsStopped());
    }
  }

  Future<void> _onPause(TtsPause event, Emitter<TtsState> emit) async {
    await _pauseSpeaking();
    if (!_usePlaybackUpdates) {
      emit(const TtsPaused());
    }
  }

  void _onPlaybackReported(
    TtsPlaybackReported event,
    Emitter<TtsState> emit,
  ) {
    switch (event.update.status) {
      case TtsPlaybackStatus.started:
        emit(TtsSpeaking(event.update.text));
        break;
      case TtsPlaybackStatus.stopped:
        emit(const TtsStopped());
        break;
      case TtsPlaybackStatus.paused:
        emit(const TtsPaused());
        break;
      case TtsPlaybackStatus.error:
        emit(TtsError(event.update.message ?? 'TTS playback error'));
        break;
    }
  }

  @override
  Future<void> close() async {
    await _playbackSubscription?.cancel();
    return super.close();
  }
}
