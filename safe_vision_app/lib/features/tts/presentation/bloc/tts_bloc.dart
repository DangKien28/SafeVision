import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../features/settings/domain/repositories/settings_repository.dart';
import '../../../../features/tts/domain/entities/tts_playback_update.dart';
import '../../../../features/tts/domain/usecases/pause_speaking_usecase.dart';
import '../../../../features/tts/domain/usecases/speak_warning_usecase.dart';
import '../../../../features/tts/domain/usecases/stop_speaking_usecase.dart';
import 'tts_event.dart';
import 'tts_state.dart';

class _TtsErrorReceived extends TtsEvent {
  const _TtsErrorReceived(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class TtsBloc extends Bloc<TtsEvent, TtsState> {
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
        super(const TtsInitial()) {
    on<TtsSpeak>(_onSpeak);
    on<TtsStop>(_onStop);
    on<TtsPause>(_onPause);
    // FIX 2: register handler for the private error event
    on<_TtsErrorReceived>(_onErrorReceived);

    // Optional stream from the native engine so the bloc can mirror the real
    // playback state (started / stopped by the OS).
    if (playbackUpdates != null) {
      _playbackSub = playbackUpdates.listen(_onPlaybackUpdate);
    }
  }

  final SpeakWarningUsecase _speakWarning;
  final StopSpeakingUsecase _stopSpeaking;
  final PauseSpeakingUsecase _pauseSpeaking;
  final SettingsRepository _settingsRepository;

  StreamSubscription<TtsPlaybackUpdate>? _playbackSub;

  // ── Event handlers ─────────────────────────────────────────────────────────

  Future<void> _onSpeak(TtsSpeak event, Emitter<TtsState> emit) async {
    final voiceEnabled = await _settingsRepository.getVoiceEnabled();

    if (!voiceEnabled) {
      await _stopSpeaking();
      // Guard: don't re-emit TtsStopped if already stopped.
      if (state is! TtsStopped) emit(const TtsStopped());
      return;
    }

    try {
      if (event.immediate) {
        await _speakWarning.immediate(event.text);
      } else {
        await _speakWarning(event.text);
      }
      emit(TtsSpeaking(event.text));
    } catch (e) {
      debugPrint('[TtsBloc] speak error: $e');
      emit(TtsError(e.toString()));
    }
  }

  Future<void> _onStop(TtsStop event, Emitter<TtsState> emit) async {
    try {
      await _stopSpeaking();
    } catch (e) {
      debugPrint('[TtsBloc] stop error (ignored): $e');
    }
    emit(const TtsStopped());
  }

  Future<void> _onPause(TtsPause event, Emitter<TtsState> emit) async {
    try {
      await _pauseSpeaking();
    } catch (e) {
      debugPrint('[TtsBloc] pause error (ignored): $e');
    }
    emit(const TtsPaused());
  }

  void _onErrorReceived(_TtsErrorReceived event, Emitter<TtsState> emit) {
    emit(TtsError(event.message));
  }

  // ── Playback stream ────────────────────────────────────────────────────────

  void _onPlaybackUpdate(TtsPlaybackUpdate update) {
    switch (update.status) {
      case TtsPlaybackStatus.started:
        if (update.text != null) add(TtsSpeak(update.text!, immediate: false));
        break;
      case TtsPlaybackStatus.stopped:
        add(const TtsStop());
        break;
      case TtsPlaybackStatus.error:
        // FIX 2: route through a registered on<> handler instead of calling
        // emit() directly (which is @visibleForTesting outside handlers).
        if (!isClosed) {
          add(_TtsErrorReceived(update.error ?? 'playback error'));
        }
        break;
    }
  }

  @override
  Future<void> close() async {
    await _playbackSub?.cancel();
    return super.close();
  }
}
