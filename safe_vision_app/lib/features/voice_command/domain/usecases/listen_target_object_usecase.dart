import '../../../../core/usecases/usecase.dart';
import '../repositories/voice_command_repository.dart';

class ListenTargetObjectParams {
  final Duration listenFor;
  final Duration pauseFor;
  final String localeId;

  const ListenTargetObjectParams({
    this.listenFor = const Duration(seconds: 4),
    this.pauseFor = const Duration(seconds: 2),
    this.localeId = 'vi_VN',
  });
}

class ListenTargetObjectUsecase
    implements UseCase<String?, ListenTargetObjectParams> {
  final VoiceCommandRepository _repository;

  ListenTargetObjectUsecase(this._repository);

  @override
  Future<String?> call(ListenTargetObjectParams params) {
    return _repository.listenObjectName(
      listenFor: params.listenFor,
      pauseFor: params.pauseFor,
      localeId: params.localeId,
    );
  }
}
