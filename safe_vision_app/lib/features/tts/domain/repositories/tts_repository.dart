abstract class TtsRepository {
  Future<void> initialize();
  Future<void> speakWarning(String text);
  Future<void> speakImmediate(String text);
  Future<void> stop();
  Future<void> pause();
  bool get isSpeaking;
}