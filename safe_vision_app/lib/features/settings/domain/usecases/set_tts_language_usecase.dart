import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

class SetTtsLanguageParams {
  final String language;

  const SetTtsLanguageParams(this.language);
}

class SetTtsLanguageUsecase implements UseCase<void, SetTtsLanguageParams> {
  final SettingsRepository _repository;

  SetTtsLanguageUsecase(this._repository);

  @override
  Future<void> call(SetTtsLanguageParams params) {
    return _repository.setTtsLanguage(params.language);
  }
}
