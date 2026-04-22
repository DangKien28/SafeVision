/// Static helpers for building consistent TTS phrases across the app.
/// This keeps message formatting separate from the business logic in
/// [DetectionObject] and [TtsService].
class VoiceHelper {
  VoiceHelper._();

  static const Map<String, String> _labelMap = {
    'ban': 'bàn',
    'bicycle': 'xe đạp',
    'bus': 'xe buýt',
    'cau_thang': 'cầu thang',
    'car': 'xe hơi',
    'cat': 'mèo',
    'chair': 'ghế',
    'dog': 'chó',
    'ghe': 'ghế',
    'motorbike': 'xe máy',
    'motorcycle': 'xe máy',
    'nguoi_di_bo': 'người đi bộ',
    'pedestrian': 'người đi bộ',
    'person': 'người đi bộ',
    'phone': 'điện thoại',
    'stair': 'cầu thang',
    'stairs': 'cầu thang',
    'table': 'bàn',
    'tree': 'cây',
    'truck': 'xe tải',
    'xe': 'xe',
  };

  static const Map<String, String> _aliasToCanonical = {
    'ban': 'table',
    'bàn': 'table',
    'table': 'table',
    'ghe': 'chair',
    'ghế': 'chair',
    'chair': 'chair',
    'cau thang': 'stairs',
    'cầu thang': 'stairs',
    'stair': 'stairs',
    'stairs': 'stairs',
    'xe dap': 'bicycle',
    'xe đạp': 'bicycle',
    'bicycle': 'bicycle',
    'xe may': 'motorbike',
    'xe máy': 'motorbike',
    'motorbike': 'motorbike',
    'motorcycle': 'motorbike',
    'xe hoi': 'car',
    'xe hơi': 'car',
    'car': 'car',
    'xe buyt': 'bus',
    'xe buýt': 'bus',
    'bus': 'bus',
    'xe tai': 'truck',
    'xe tải': 'truck',
    'truck': 'truck',
    'cho': 'dog',
    'chó': 'dog',
    'dog': 'dog',
    'meo': 'cat',
    'mèo': 'cat',
    'cat': 'cat',
    'nguoi di bo': 'person',
    'người đi bộ': 'person',
    'person': 'person',
    'pedestrian': 'person',
    'dien thoai': 'phone',
    'điện thoại': 'phone',
    'phone': 'phone',
    'cay': 'tree',
    'cây': 'tree',
    'tree': 'tree',
    'xe': 'vehicle',
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

  /// Canonical key used to compare model labels and spoken object names.
  /// Returns `null` when input is empty after trimming.
  static String? canonicalLabelKey(String raw) {
    final cleaned = raw.trim().toLowerCase().replaceAll('_', ' ');
    if (cleaned.isEmpty) return null;
    return _aliasToCanonical[cleaned] ?? cleaned;
  }

  static String modelLoaded() => 'Hệ thống sẵn sàng';
  static String noObjectFound() => 'Không phát hiện vật thể';
  static String systemError() => 'Lỗi hệ thống, vui lòng thử lại';
}
