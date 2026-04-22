import '../repositories/detection_repository.dart';
import '../../../../core/usecases/usecase.dart';

/// Releases the TFLite interpreter inside the isolate when detection stops.
///
/// Keeping this as its own use case allows the presentation layer
/// ([DetectionBloc]) to stay unaware of [DetectionRepository], following
/// the Clean Architecture dependency rule.
class CloseModelUsecase implements UseCase<void, NoParams> {
  final DetectionRepository _repository;
  CloseModelUsecase(this._repository);

  @override
  Future<void> call(NoParams params) => _repository.closeModel();
}
