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

// ── Private internal events ───────────────────────────────────────────────────

class _TtsErrorReceived extends TtsEvent {
  const _TtsErrorReceived(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// FIX (Bug 9): New internal event to reflect that the native engine has
// confirmed speech started.  Previously the code dispatched a public TtsSpeak
// event on receipt of TtsPlaybackStatus.started, which caused the BLoC to
// call speakWarning() again → the engine received a second speak() call →
// reported started again → infinite feedback loop.
//
// The fix routes the "started" signal through a private event that ONLY updates
// state to TtsSpeaking(text) without triggering another speakWarning() call.
class _TtsPlaybackStarted extends TtsEvent {
  const _TtsPlaybackStarted(this.text);
  final String text;
  @override
  List<Object?> get props => [text];
}

class _TtsPlaybackStopped extends TtsEvent {
  const _TtsPlaybackStopped();
}

// ── TtsBloc ───────────────────────────────────────────────────────────────────

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
    on<_TtsErrorReceived>(_onErrorReceived);
    // FIX (Bug 9): register handler for the new playback-started internal event.
    on<_TtsPlaybackStarted>(_onPlaybackStarted);
    on<_TtsPlaybackStopped>(_onPlaybackStopped);

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

  void _onPlaybackStarted(_TtsPlaybackStarted event, Emitter<TtsState> emit) {
    emit(TtsSpeaking(event.text));
  }

  void _onPlaybackStopped(_TtsPlaybackStopped event, Emitter<TtsState> emit) {
    emit(const TtsStopped());
  }

  // ── Playback stream ────────────────────────────────────────────────────────

  void _onPlaybackUpdate(TtsPlaybackUpdate update) {
    switch (update.status) {
      case TtsPlaybackStatus.started:
        if (update.text != null && !isClosed) {
          add(_TtsPlaybackStarted(update.text!));
        }
        break;
      case TtsPlaybackStatus.stopped:
        if (!isClosed) add(const _TtsPlaybackStopped());
        break;
      case TtsPlaybackStatus.error:
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
