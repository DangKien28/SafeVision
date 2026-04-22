import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/detection_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../../tts/domain/usecases/configure_tts_usecase.dart';
import '../../../tts/domain/usecases/stop_speaking_usecase.dart';
import 'settings_event.dart';
import 'settings_state.dart';

/// Manages user settings and propagates them to dependent subsystems.
///
/// Whenever a setting changes, this BLoC is responsible for:
/// - Saving it through [SettingsRepository].
/// - Updating [DetectionConfig] when inference behavior is affected.
/// - Calling [ConfigureTtsUsecase] to refresh the FlutterTts engine.
///
/// Important invariant: when the TTS language changes, the current
/// [speechRate] must also be passed into [ConfigureTtsUsecase] so the engine
/// does not reset to its default speed.
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository _repository;
  final ConfigureTtsUsecase _configureTts;
  final StopSpeakingUsecase _stopSpeaking;
  final DetectionConfig _detectionConfig;

  SettingsBloc(
    this._repository,
    this._configureTts,
    this._stopSpeaking,
    this._detectionConfig,
  ) : super(const SettingsState()) {
    on<SettingsLoaded>(_onLoaded);
    on<SettingsSpeechRateChanged>(_onSpeechRate);
    on<SettingsConfidenceChanged>(_onConfidence);
    on<SettingsVoiceToggled>(_onVoice);
    on<SettingsConfidencePanelToggled>(_onPanel);
    on<SettingsTtsLanguageChanged>(_onLanguage);
  }

  Future<void> _onLoaded(
    SettingsLoaded event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));

    final speechRate = await _repository.getSpeechRate();
    final confThresh = await _repository.getConfidenceThreshold();
    final voiceEnabled = await _repository.getVoiceEnabled();
    final showPanel = await _repository.getShowConfidencePanel();

    // Language is intentionally hardcoded to vi-VN rather than read from
    // _repository.getTtsLanguage(). The repository getter exists for future
    // multi-language support but is currently dead API surface.
    final language = AppConstants.ttsLanguage;

    _detectionConfig.setConfidenceThreshold(confThresh);
    await _repository.setTtsLanguage(language);
    await _configureTts(speechRate: speechRate, language: language);

    emit(state.copyWith(
      speechRate: speechRate,
      confidenceThreshold: confThresh,
      voiceEnabled: voiceEnabled,
      showConfidencePanel: showPanel,
      isLoading: false,
    ));
  }

  Future<void> _onSpeechRate(
    SettingsSpeechRateChanged e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setSpeechRate(e.rate);
    // Pass the current language together with the new rate so the engine
    // does not reset to its defaults.
    await _configureTts(speechRate: e.rate, language: AppConstants.ttsLanguage);
    emit(state.copyWith(speechRate: e.rate));
  }

  Future<void> _onConfidence(
    SettingsConfidenceChanged e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setConfidenceThreshold(e.threshold);
    // Update DetectionConfig immediately so the next inference frame uses the
    // new threshold without restarting the model.
    _detectionConfig.setConfidenceThreshold(e.threshold);
    emit(state.copyWith(confidenceThreshold: e.threshold));
  }

  Future<void> _onVoice(
    SettingsVoiceToggled e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setVoiceEnabled(e.enabled);
    if (!e.enabled) await _stopSpeaking();
    emit(state.copyWith(voiceEnabled: e.enabled));
  }

  Future<void> _onPanel(
    SettingsConfidencePanelToggled e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setShowConfidencePanel(e.show);
    emit(state.copyWith(showConfidencePanel: e.show));
  }

  /// Changes the TTS language while preserving the current [speechRate].
  /// [ConfigureTtsUsecase] must reinitialize the engine with both values,
  /// otherwise it may fall back to the default rate.
  Future<void> _onLanguage(
    SettingsTtsLanguageChanged e,
    Emitter<SettingsState> emit,
  ) async {
    // Language is locked to vi-VN. This handler reconfigures the TTS engine
    // while preserving the current speechRate so the engine does not reset to
    // its default speed after a lifecycle event.
    const language = AppConstants.ttsLanguage;
    await _repository.setTtsLanguage(language);
    await _configureTts(
      language: language,
      speechRate: state.speechRate,
    );
    emit(state.copyWith(ttsLanguage: language));
  }
}
