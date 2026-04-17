import '../../../../core/usecases/usecase.dart';
import '../repositories/detection_repository.dart';

/// Closes the TFLite model and terminates the inference isolate.
///
/// Always call via `usecase.call(const NoParams())`.
class CloseModelUsecase implements UseCase<void, NoParams> {
  CloseModelUsecase(this._repository);
  final DetectionRepository _repository;
 
  @override
  Future<void> call(NoParams params) => _repository.closeModel();
}
