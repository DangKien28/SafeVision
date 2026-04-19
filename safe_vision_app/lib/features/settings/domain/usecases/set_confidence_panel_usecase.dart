import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

class SetConfidencePanelParams {
  final bool show;

  const SetConfidencePanelParams(this.show);
}

class SetConfidencePanelUsecase
    implements UseCase<void, SetConfidencePanelParams> {
  final SettingsRepository _repository;

  SetConfidencePanelUsecase(this._repository);

  @override
  Future<void> call(SetConfidencePanelParams params) {
    return _repository.setShowConfidencePanel(params.show);
  }
}
