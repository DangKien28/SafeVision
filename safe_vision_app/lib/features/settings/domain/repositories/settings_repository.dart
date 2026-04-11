abstract class SettingsRepository {
  Future<double> getSpeechRate();
  Future<void> setSpeechRate(double rate);

  Future<double> getConfidenceThreshold();
  Future<void> setConfidenceThreshold(double threshold);

  Future<bool> getVoiceEnabled();
  Future<void> setVoiceEnabled(bool enabled);

  Future<bool> getShowConfidencePanel();
  Future<void> setShowConfidencePanel(bool show);

  Future<String> getTtsLanguage();
  Future<void> setTtsLanguage(String langCode);
}
