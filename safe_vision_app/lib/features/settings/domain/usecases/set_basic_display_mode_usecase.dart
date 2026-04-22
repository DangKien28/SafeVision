import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

class SetBasicDisplayModeParams {
  final bool enabled;

  const SetBasicDisplayModeParams(this.enabled);
}

class SetBasicDisplayModeUsecase
    implements UseCase<void, SetBasicDisplayModeParams> {
  final SettingsRepository _repository;

  SetBasicDisplayModeUsecase(this._repository);

  @override
  Future<void> call(SetBasicDisplayModeParams params) {
    return _repository.setBasicDisplayModeEnabled(params.enabled);
  }
}
