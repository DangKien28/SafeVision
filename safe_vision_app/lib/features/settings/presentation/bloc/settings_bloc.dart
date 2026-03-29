import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safe_vision_app/features/tts/data/datasources/tts_service.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository _repository;
  final TtsService _ttsService;

  SettingsBloc(this._repository, this._ttsService)
      : super(const SettingsState()) {
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
    final language = await _repository.getTtsLanguage();
    emit(state.copyWith(
      speechRate: speechRate,
      confidenceThreshold: confThresh,
      voiceEnabled: voiceEnabled,
      showConfidencePanel: showPanel,
      ttsLanguage: language,
      isLoading: false,
    ));
  }

  Future<void> _onSpeechRate(
    SettingsSpeechRateChanged e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setSpeechRate(e.rate);
    await _ttsService.initialize(speechRate: e.rate);
    emit(state.copyWith(speechRate: e.rate));
  }

  Future<void> _onConfidence(
    SettingsConfidenceChanged e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setConfidenceThreshold(e.threshold);
    emit(state.copyWith(confidenceThreshold: e.threshold));
  }

  Future<void> _onVoice(
    SettingsVoiceToggled e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setVoiceEnabled(e.enabled);
    if (!e.enabled) await _ttsService.stop();
    emit(state.copyWith(voiceEnabled: e.enabled));
  }

  Future<void> _onPanel(
    SettingsConfidencePanelToggled e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setShowConfidencePanel(e.show);
    emit(state.copyWith(showConfidencePanel: e.show));
  }

  Future<void> _onLanguage(
    SettingsTtsLanguageChanged e,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setTtsLanguage(e.lang);
    emit(state.copyWith(ttsLanguage: e.lang));
  }
}
