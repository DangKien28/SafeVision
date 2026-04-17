abstract class TtsRepository {
  Future<void> initialize();
  Future<bool> speakWarning(String text);
  Future<bool> speakImmediate(String text);
  Future<void> stop();
  Future<void> pause();
  bool get isSpeaking;
  Future<void> configure({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  });
}
