class SettingsPreferences {
  final double speechRate;
  final double confidenceThreshold;
  final bool voiceEnabled;
  final bool showConfidencePanel;
  final bool basicDisplayModeEnabled;
  final String ttsLanguage;

  const SettingsPreferences({
    required this.speechRate,
    required this.confidenceThreshold,
    required this.voiceEnabled,
    required this.showConfidencePanel,
    required this.basicDisplayModeEnabled,
    required this.ttsLanguage,
  });
}
