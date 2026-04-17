abstract class VoiceHelper {
  VoiceHelper._();

  static const Map<String, String> _labels = {
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

  /// Returns the Vietnamese display name for a raw model label.
  static String normalizeLabel(String raw) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty) return 'vật thể';
    return _labels[key] ?? key.replaceAll('_', ' ');
  }

  /// Builds a complete TTS warning sentence.
  static String buildWarning({
    required String label,
    required String position,
    required String distance,
  }) =>
      'Cảnh báo! ${normalizeLabel(label)} ở $position, $distance.';

  static String modelLoaded() => 'Hệ thống sẵn sàng';
  static String noObjectFound() => 'Không phát hiện vật thể';
  static String systemError() => 'Lỗi hệ thống, vui lòng thử lại';
}
