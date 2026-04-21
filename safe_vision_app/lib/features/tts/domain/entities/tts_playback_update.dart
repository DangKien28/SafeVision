enum TtsPlaybackStatus {
  started,
  stopped,
  paused,
  error,
}

class TtsPlaybackUpdate {
  const TtsPlaybackUpdate({
    required this.status,
    this.text = '',
    this.message,
  });

  final TtsPlaybackStatus status;
  final String text;
  final String? message;
}
