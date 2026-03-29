import '../repositories/tts_repository.dart';

class StopSpeakingUsecase {
  final TtsRepository _repository;
  StopSpeakingUsecase(this._repository);
  Future<void> call() => _repository.stop();
}