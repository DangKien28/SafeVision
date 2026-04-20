import 'package:equatable/equatable.dart';

import '../../../../core/constants/app_constants.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.speechRate = AppConstants.ttsSpeechRate,
    this.confidenceThreshold = AppConstants.confidenceThreshold,
    this.voiceEnabled = true,
    this.showConfidencePanel = true,
    this.basicDisplayModeEnabled = AppConstants.basicModeDefaultEnabled,
    this.ttsLanguage = '',
    this.isLoading = false,
  });

  final double speechRate;
  final double confidenceThreshold;
  final bool voiceEnabled;
  final bool showConfidencePanel;
  final bool basicDisplayModeEnabled;
  final String ttsLanguage;
  final bool isLoading;

  SettingsState copyWith({
    double? speechRate,
    double? confidenceThreshold,
    bool? voiceEnabled,
    bool? showConfidencePanel,
    bool? basicDisplayModeEnabled,
    String? ttsLanguage,
    bool? isLoading,
  }) =>
      SettingsState(
        speechRate: speechRate ?? this.speechRate,
        confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
        voiceEnabled: voiceEnabled ?? this.voiceEnabled,
        showConfidencePanel: showConfidencePanel ?? this.showConfidencePanel,
        basicDisplayModeEnabled:
            basicDisplayModeEnabled ?? this.basicDisplayModeEnabled,
        ttsLanguage: ttsLanguage ?? this.ttsLanguage,
        isLoading: isLoading ?? this.isLoading,
      );

  @override
  List<Object?> get props => [
        speechRate,
        confidenceThreshold,
        voiceEnabled,
        showConfidencePanel,
        basicDisplayModeEnabled,
        ttsLanguage,
        isLoading,
      ];
}
