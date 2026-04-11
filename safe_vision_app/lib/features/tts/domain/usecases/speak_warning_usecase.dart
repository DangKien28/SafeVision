import '../repositories/tts_repository.dart';

class SpeakWarningUsecase {
  final TtsRepository _repository;
  SpeakWarningUsecase(this._repository);

  Future<bool> call(String text) => _repository.speakWarning(text);

  Future<bool> immediate(String text) => _repository.speakImmediate(text);
}
