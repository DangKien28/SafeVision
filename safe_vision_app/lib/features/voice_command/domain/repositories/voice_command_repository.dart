abstract class VoiceCommandRepository {
  Future<String?> listenObjectName({
    Duration listenFor = const Duration(seconds: 4),
    Duration pauseFor = const Duration(seconds: 2),
    String localeId = 'vi_VN',
  });
}
