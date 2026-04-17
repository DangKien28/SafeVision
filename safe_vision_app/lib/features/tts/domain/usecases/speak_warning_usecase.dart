import '../repositories/tts_repository.dart';

class SpeakWarningUsecase {
  SpeakWarningUsecase(this._repository);
  final TtsRepository _repository;
 
  Future<bool> call(String text) => _repository.speakWarning(text);
  Future<bool> immediate(String text) => _repository.speakImmediate(text);
}