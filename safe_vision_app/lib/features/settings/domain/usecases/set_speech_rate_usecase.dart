import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

class SetSpeechRateParams {
  final double rate;

  const SetSpeechRateParams(this.rate);
}

class SetSpeechRateUsecase implements UseCase<void, SetSpeechRateParams> {
  final SettingsRepository _repository;

  SetSpeechRateUsecase(this._repository);

  @override
  Future<void> call(SetSpeechRateParams params) {
    return _repository.setSpeechRate(params.rate);
  }
}
