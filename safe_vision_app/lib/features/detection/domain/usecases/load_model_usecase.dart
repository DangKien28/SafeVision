import '../repositories/detection_repository.dart';
import '../../../../core/usecases/usecase.dart';

class LoadModelUsecase implements UseCase<void, NoParams> {
  final DetectionRepository _repository;
  LoadModelUsecase(this._repository);

  @override
  Future<void> call(NoParams params) => _repository.loadModel();

  /// Shortcut — gọi không cần truyền params
  Future<void> load() => _repository.loadModel();
}