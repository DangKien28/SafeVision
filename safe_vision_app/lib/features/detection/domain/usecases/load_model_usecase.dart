import '../repositories/detection_repository.dart';
import '../../../../core/usecases/usecase.dart';

/// Loads the TFLite model and spawns the inference isolate when detection
/// starts.
///
/// Keeping this as a separate use case ensures that [DetectionBloc] depends
/// only on domain abstractions instead of the data-layer implementation.
class LoadModelUsecase implements UseCase<void, NoParams> {
  final DetectionRepository _repository;
  LoadModelUsecase(this._repository);

  @override
  Future<void> call(NoParams params) => _repository.loadModel();
}
