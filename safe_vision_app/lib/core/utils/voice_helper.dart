/// Static helpers for building consistent TTS phrases across the app.
/// This keeps message formatting separate from the business logic in
/// [DetectionObject] and [TtsService].
class VoiceHelper {
  VoiceHelper._();

  static const Map<String, String> _labelMap = {
    'ban': 'bàn',
    'cau_thang': 'cầu thang',
    'cay': 'cây',
    'ghe': 'ghế',
    'nguoi_di_bo': 'người đi bộ',
    'xe': 'xe hơi',
    'cua': 'cửa',
    'ho': 'hố',
    'balo': 'ba lô',
    'vi': 'ví',
    'lua': 'lửa',
    'laptop': 'laptop',
    'dien_thoai': 'điện thoại',
  };

  /// Full warning sentence including object name, horizontal position,
  /// and estimated distance. The phrasing is tuned for natural playback
  /// by the Vietnamese TTS engine.
  static String buildWarning({
    required String label,
    required String position,
    required String distance,
  }) =>
      'Cảnh báo! ${normalizeLabel(label)} ở $position, $distance.';

  static String normalizeLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return 'vật thể';

    final key = trimmed.toLowerCase();
    if (_labelMap.containsKey(key)) {
      return _labelMap[key]!;
    }

    return trimmed.replaceAll('_', ' ');
  }

  static String modelLoaded() => 'Hệ thống sẵn sàng';
  static String noObjectFound() => 'Không phát hiện vật thể';
  static String systemError() => 'Lỗi hệ thống, vui lòng thử lại';
}
