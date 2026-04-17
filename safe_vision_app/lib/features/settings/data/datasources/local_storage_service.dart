// Excluded from coverage: depends on SharedPreferences (native plugin).

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';

class LocalStorageService {
  LocalStorageService();

  static const _keySpeechRate = 'speechRate';
  static const _keyConfidence = 'confidenceThreshold';
  static const _keyVoiceEnabled = 'voiceEnabled';
  static const _keyShowConfidence = 'showConfidencePanel';
  static const _keyTtsLanguage = 'ttsLanguage';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<double> getSpeechRate() async =>
      (await _prefs).getDouble(_keySpeechRate) ?? AppConstants.ttsSpeechRate;
  Future<void> setSpeechRate(double v) async =>
      (await _prefs).setDouble(_keySpeechRate, v);

  Future<double> getConfidenceThreshold() async =>
      (await _prefs).getDouble(_keyConfidence) ??
      AppConstants.confidenceThreshold;
  Future<void> setConfidenceThreshold(double v) async =>
      (await _prefs).setDouble(_keyConfidence, v);

  Future<bool> getVoiceEnabled() async =>
      (await _prefs).getBool(_keyVoiceEnabled) ?? true;
  Future<void> setVoiceEnabled(bool v) async =>
      (await _prefs).setBool(_keyVoiceEnabled, v);

  Future<bool> getShowConfidencePanel() async =>
      (await _prefs).getBool(_keyShowConfidence) ?? true;
  Future<void> setShowConfidencePanel(bool v) async =>
      (await _prefs).setBool(_keyShowConfidence, v);

  Future<String> getTtsLanguage() async =>
      (await _prefs).getString(_keyTtsLanguage) ?? AppConstants.ttsLanguage;
  Future<void> setTtsLanguage(String v) async =>
      (await _prefs).setString(_keyTtsLanguage, v);
}
