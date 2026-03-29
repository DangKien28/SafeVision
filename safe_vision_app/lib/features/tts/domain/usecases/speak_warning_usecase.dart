import '../repositories/tts_repository.dart';

class SpeakWarningUsecase {
  final TtsRepository _repository;
  SpeakWarningUsecase(this._repository);

  /// Đọc cảnh báo thông thường (có cooldown)
  Future<void> call(String text) => _repository.speakWarning(text);

  /// Đọc ngay lập tức — cảnh báo khẩn cấp
  Future<void> immediate(String text) => _repository.speakImmediate(text);
}