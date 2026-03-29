import 'package:equatable/equatable.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();
  @override List<Object?> get props => [];
}

class SettingsLoaded                  extends SettingsEvent { const SettingsLoaded(); }
class SettingsSpeechRateChanged       extends SettingsEvent {
  final double rate;
  const SettingsSpeechRateChanged(this.rate);
  @override List<Object?> get props => [rate];
}
class SettingsConfidenceChanged       extends SettingsEvent {
  final double threshold;
  const SettingsConfidenceChanged(this.threshold);
  @override List<Object?> get props => [threshold];
}
class SettingsVoiceToggled            extends SettingsEvent {
  final bool enabled;
  const SettingsVoiceToggled(this.enabled);
  @override List<Object?> get props => [enabled];
}
class SettingsConfidencePanelToggled  extends SettingsEvent {
  final bool show;
  const SettingsConfidencePanelToggled(this.show);
  @override List<Object?> get props => [show];
}
class SettingsTtsLanguageChanged      extends SettingsEvent {
  final String lang;
  const SettingsTtsLanguageChanged(this.lang);
  @override List<Object?> get props => [lang];
}