import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

class SetVoiceEnabledParams {
  final bool enabled;

  const SetVoiceEnabledParams(this.enabled);
}

class SetVoiceEnabledUsecase implements UseCase<void, SetVoiceEnabledParams> {
  final SettingsRepository _repository;

  SetVoiceEnabledUsecase(this._repository);

  @override
  Future<void> call(SetVoiceEnabledParams params) {
    return _repository.setVoiceEnabled(params.enabled);
  }
}
