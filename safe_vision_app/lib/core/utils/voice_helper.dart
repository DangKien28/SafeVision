/// Các câu cảnh báo tiếng Việt chuẩn, dùng cho TTS
class VoiceHelper {
  VoiceHelper._();

  static String buildWarning({
    required String label,
    required String position,
    required String distance,
  }) =>
      'Cảnh báo! $label $position, $distance';

  static String modelLoaded()   => 'Hệ thống sẵn sàng';
  static String noObjectFound() => 'Không phát hiện vật thể';
  static String systemError()   => 'Lỗi hệ thống, vui lòng thử lại';
}