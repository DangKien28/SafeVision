// lib/features/settings/presentation/bloc/settings_event.dart

import 'package:equatable/equatable.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();
  @override
  List<Object?> get props => [];
}

class SettingsLoaded extends SettingsEvent {
  const SettingsLoaded();
}

class SettingsSpeechRateChanged extends SettingsEvent {
  final double rate;
  const SettingsSpeechRateChanged(this.rate);
  @override
  List<Object?> get props => [rate];
}

class SettingsConfidenceChanged extends SettingsEvent {
  final double threshold;
  const SettingsConfidenceChanged(this.threshold);
  @override
  List<Object?> get props => [threshold];
}

class SettingsVoiceToggled extends SettingsEvent {
  final bool enabled;
  const SettingsVoiceToggled(this.enabled);
  @override
  List<Object?> get props => [enabled];
}

class SettingsConfidencePanelToggled extends SettingsEvent {
  final bool show;
  const SettingsConfidencePanelToggled(this.show);
  @override
  List<Object?> get props => [show];
}

/// Language is locked to [AppConstants.ttsLanguage] (vi-VN) for this release.
/// This event exists to let the UI trigger a TTS engine reconfiguration
/// (e.g. after an app lifecycle resume) without carrying a language parameter
/// that would be silently ignored.
class SettingsTtsLanguageChanged extends SettingsEvent {
  const SettingsTtsLanguageChanged();

  @override
  List<Object?> get props => [];
}
