abstract class VoiceCommandDatasource {
  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 4),
    Duration pauseFor = const Duration(seconds: 2),
    String localeId = 'vi_VN',
  });
}
