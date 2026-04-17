import '../repositories/tts_repository.dart';

class PauseSpeakingUsecase {
  PauseSpeakingUsecase(this._repository);
  final TtsRepository _repository;

  Future<void> call() => _repository.pause();
}
