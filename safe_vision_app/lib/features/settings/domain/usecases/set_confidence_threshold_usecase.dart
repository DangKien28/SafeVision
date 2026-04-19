import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

class SetConfidenceThresholdParams {
  final double threshold;

  const SetConfidenceThresholdParams(this.threshold);
}

class SetConfidenceThresholdUsecase
    implements UseCase<void, SetConfidenceThresholdParams> {
  final SettingsRepository _repository;

  SetConfidenceThresholdUsecase(this._repository);

  @override
  Future<void> call(SetConfidenceThresholdParams params) {
    return _repository.setConfidenceThreshold(params.threshold);
  }
}
