import '../repositories/tts_repository.dart';

class StopSpeakingUsecase {
  StopSpeakingUsecase(this._repository);
  final TtsRepository _repository;

  Future<void> call() => _repository.stop();
}
