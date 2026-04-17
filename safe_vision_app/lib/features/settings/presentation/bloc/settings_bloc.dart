import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
 
import '../../../../core/config/detection_config.dart';
import '../../../../features/settings/domain/repositories/settings_repository.dart';
import '../../../../features/tts/domain/usecases/configure_tts_usecase.dart';
import '../../../../features/tts/domain/usecases/stop_speaking_usecase.dart';
import 'settings_event.dart';
import 'settings_state.dart';
 
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc(
    this._repository,
    this._configureTts,
    this._stopSpeaking,
    this._detectionConfig,
  ) : super(const SettingsState()) {
    on<SettingsLoaded>(_onLoaded);
    on<SettingsSpeechRateChanged>(_onSpeechRateChanged);
    on<SettingsConfidenceChanged>(_onConfidenceChanged);
    on<SettingsVoiceToggled>(_onVoiceToggled);
    on<SettingsConfidencePanelToggled>(_onConfidencePanelToggled);
    on<SettingsTtsLanguageChanged>(_onTtsLanguageChanged);
  }
 
  final SettingsRepository _repository;
  final ConfigureTtsUsecase _configureTts;
  final StopSpeakingUsecase _stopSpeaking;
  final DetectionConfig _detectionConfig;
 
  // SafeVision is always Vietnamese — language is never actually changed.
  static const _forcedLanguage = 'vi-VN';
 
  // ── Handlers ───────────────────────────────────────────────────────────────
 
  Future<void> _onLoaded(
    SettingsLoaded event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final speechRate          = await _repository.getSpeechRate();
      final confidenceThreshold = await _repository.getConfidenceThreshold();
      final voiceEnabled        = await _repository.getVoiceEnabled();
      final showConfidencePanel = await _repository.getShowConfidencePanel();
      final ttsLanguage         = await _repository.getTtsLanguage();
 
      _detectionConfig.setConfidenceThreshold(confidenceThreshold);
 
      // Re-configure TTS engine so it honours the persisted settings.
      await _configureTts(
        language:   ttsLanguage.isNotEmpty ? ttsLanguage : _forcedLanguage,
        speechRate: speechRate,
        pitch:      null,
        volume:     null,
      );
 
      emit(state.copyWith(
        speechRate:          speechRate,
        confidenceThreshold: confidenceThreshold,
        voiceEnabled:        voiceEnabled,
        showConfidencePanel: showConfidencePanel,
        ttsLanguage:         ttsLanguage.isNotEmpty ? ttsLanguage : _forcedLanguage,
        isLoading:           false,
      ));
    } catch (e) {
      debugPrint('[SettingsBloc] load error: $e');
      emit(state.copyWith(isLoading: false));
    }
  }
 
  Future<void> _onSpeechRateChanged(
    SettingsSpeechRateChanged event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setSpeechRate(event.rate);
    // BUG FIX (SV-006): always pass BOTH rate AND language to configure().
    // Passing only rate resets the language to the engine default.
    await _configureTts(
      language:   _forcedLanguage,
      speechRate: event.rate,
      pitch:      null,
      volume:     null,
    );
    emit(state.copyWith(speechRate: event.rate));
  }
 
  Future<void> _onConfidenceChanged(
    SettingsConfidenceChanged event,
    Emitter<SettingsState> emit,
  ) async {
    // Apply immediately to DetectionConfig so the next frame uses the new
    // threshold without a model restart.
    _detectionConfig.setConfidenceThreshold(event.threshold);
    await _repository.setConfidenceThreshold(event.threshold);
    emit(state.copyWith(confidenceThreshold: event.threshold));
  }
 
  Future<void> _onVoiceToggled(
    SettingsVoiceToggled event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setVoiceEnabled(event.enabled);
    if (!event.enabled) await _stopSpeaking();
    emit(state.copyWith(voiceEnabled: event.enabled));
  }
 
  Future<void> _onConfidencePanelToggled(
    SettingsConfidencePanelToggled event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setShowConfidencePanel(event.show);
    emit(state.copyWith(showConfidencePanel: event.show));
  }
 
  /// BUG FIX (SV-006): language change MUST forward the current speechRate.
  ///
  /// Previous implementation called `_configureTts(language: 'vi-VN')` without
  /// passing `speechRate`.  The TTS engine then silently reset to its own
  /// default rate, ignoring the user's setting.
  Future<void> _onTtsLanguageChanged(
    SettingsTtsLanguageChanged event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _repository.setTtsLanguage(_forcedLanguage);
      // Pass current speechRate so the engine never resets it.
      await _configureTts(
        language:   _forcedLanguage,
        speechRate: state.speechRate,
        pitch:      null,
        volume:     null,
      );
      emit(state.copyWith(ttsLanguage: _forcedLanguage, isLoading: false));
    } catch (e) {
      debugPrint('[SettingsBloc] language change error: $e');
      emit(state.copyWith(isLoading: false));
    }
  }
}
 