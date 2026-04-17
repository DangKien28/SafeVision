import 'package:equatable/equatable.dart';
 
abstract class SettingsEvent extends Equatable {
  const SettingsEvent();
  @override List<Object?> get props => [];
}
 
class SettingsLoaded extends SettingsEvent {
  const SettingsLoaded();
}
 
class SettingsSpeechRateChanged extends SettingsEvent {
  const SettingsSpeechRateChanged(this.rate);
  final double rate;
  @override List<Object?> get props => [rate];
}
 
class SettingsConfidenceChanged extends SettingsEvent {
  const SettingsConfidenceChanged(this.threshold);
  final double threshold;
  @override List<Object?> get props => [threshold];
}
 
class SettingsVoiceToggled extends SettingsEvent {
  const SettingsVoiceToggled(this.enabled);
  final bool enabled;
  @override List<Object?> get props => [enabled];
}
 
class SettingsConfidencePanelToggled extends SettingsEvent {
  const SettingsConfidencePanelToggled(this.show);
  final bool show;
  @override List<Object?> get props => [show];
}
 
/// Fired when the user requests a TTS language cycle.  SafeVision always
/// stays on Vietnamese (`vi-VN`); the event simply re-applies the current
/// state's speechRate so the engine doesn't revert to its default.
class SettingsTtsLanguageChanged extends SettingsEvent {
  const SettingsTtsLanguageChanged();
}