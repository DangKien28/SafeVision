import '../../../../core/usecases/usecase.dart';
import '../repositories/detection_repository.dart';

/// Loads the TFLite model via the repository.
///
/// Always call via `usecase.call(const NoParams())` — no convenience wrapper.
class LoadModelUsecase implements UseCase<void, NoParams> {
  LoadModelUsecase(this._repository);
  final DetectionRepository _repository;

  @override
  Future<void> call(NoParams params) => _repository.loadModel();
}
