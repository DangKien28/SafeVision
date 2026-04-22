import '../../../../core/usecases/usecase.dart';
import '../entities/settings_preferences.dart';
import '../repositories/settings_repository.dart';

class LoadSettingsUsecase implements UseCase<SettingsPreferences, NoParams> {
  final SettingsRepository _repository;

  LoadSettingsUsecase(this._repository);

  @override
  Future<SettingsPreferences> call(NoParams params) async {
    final speechRate = await _repository.getSpeechRate();
    final confidenceThreshold = await _repository.getConfidenceThreshold();
    final voiceEnabled = await _repository.getVoiceEnabled();
    final showConfidencePanel = await _repository.getShowConfidencePanel();
    final basicDisplayModeEnabled =
        await _repository.getBasicDisplayModeEnabled();
    final ttsLanguage = await _repository.getTtsLanguage();

    return SettingsPreferences(
      speechRate: speechRate,
      confidenceThreshold: confidenceThreshold,
      voiceEnabled: voiceEnabled,
      showConfidencePanel: showConfidencePanel,
      basicDisplayModeEnabled: basicDisplayModeEnabled,
      ttsLanguage: ttsLanguage,
    );
  }
}
