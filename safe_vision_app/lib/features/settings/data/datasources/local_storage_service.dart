import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';

class LocalStorageService {
  static const _keySpeechRate = 'speech_rate';
  static const _keyConfThreshold = 'confidence_threshold';
  static const _keyVoiceEnabled = 'voice_enabled';
  static const _keyShowConfPanel = 'show_confidence_panel';
  static const _keyTtsLanguage = 'tts_language';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<double> getSpeechRate() async {
    final p = await _prefs;
    return p.getDouble(_keySpeechRate) ?? AppConstants.ttsSpeechRate;
  }

  Future<void> setSpeechRate(double rate) async {
    final p = await _prefs;
    await p.setDouble(_keySpeechRate, rate);
  }

  Future<double> getConfidenceThreshold() async {
    final p = await _prefs;
    return p.getDouble(_keyConfThreshold) ?? AppConstants.confidenceThreshold;
  }

  Future<void> setConfidenceThreshold(double v) async {
    final p = await _prefs;
    await p.setDouble(_keyConfThreshold, v);
  }

  Future<bool> getVoiceEnabled() async {
    final p = await _prefs;
    return p.getBool(_keyVoiceEnabled) ?? true;
  }

  Future<void> setVoiceEnabled(bool v) async {
    final p = await _prefs;
    await p.setBool(_keyVoiceEnabled, v);
  }

  Future<bool> getShowConfidencePanel() async {
    final p = await _prefs;
    return p.getBool(_keyShowConfPanel) ?? true;
  }

  Future<void> setShowConfidencePanel(bool v) async {
    final p = await _prefs;
    await p.setBool(_keyShowConfPanel, v);
  }

  Future<String> getTtsLanguage() async {
    return AppConstants.ttsLanguage;
  }

  /// Persists the language value.
  /// Language is locked to [AppConstants.ttsLanguage] for this release.
  Future<void> setTtsLanguage(String lang) async {
    final p = await _prefs;
    await p.setString(_keyTtsLanguage, AppConstants.ttsLanguage);
  }
}
