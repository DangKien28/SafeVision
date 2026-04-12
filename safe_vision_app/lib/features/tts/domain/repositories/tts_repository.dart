abstract class TtsRepository {
  Future<void> initialize();
  Future<bool> speakWarning(String text);
  Future<bool> speakImmediate(String text);
  Future<void> stop();
  Future<void> pause();

  Future<void> configure({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  });
  bool get isSpeaking;
}
