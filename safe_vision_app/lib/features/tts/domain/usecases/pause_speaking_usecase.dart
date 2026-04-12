import '../repositories/tts_repository.dart';

class PauseSpeakingUsecase {
  final TtsRepository _repository;
  PauseSpeakingUsecase(this._repository);

  Future<void> call() => _repository.pause();
}
