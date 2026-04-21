import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/utils/voice_helper.dart';

void main() {
  group('normalizeLabel', () {
    test('maps known Vietnamese labels', () {
      expect(VoiceHelper.normalizeLabel('ban'), 'bàn');
      expect(VoiceHelper.normalizeLabel('ghe'), 'ghế');
      expect(VoiceHelper.normalizeLabel('cau_thang'), 'cầu thang');
      expect(VoiceHelper.normalizeLabel('nguoi_di_bo'), 'người đi bộ');
      expect(VoiceHelper.normalizeLabel('xe'), 'xe hơi');
      expect(VoiceHelper.normalizeLabel('cay'), 'cây');
      expect(VoiceHelper.normalizeLabel('cua'), 'cửa');
      expect(VoiceHelper.normalizeLabel('ho'), 'hố');
      expect(VoiceHelper.normalizeLabel('balo'), 'ba lô');
      expect(VoiceHelper.normalizeLabel('vi'), 'ví');
      expect(VoiceHelper.normalizeLabel('lua'), 'lửa');
      expect(VoiceHelper.normalizeLabel('laptop'), 'laptop');
      expect(VoiceHelper.normalizeLabel('dien_thoai'), 'điện thoại');
      expect(VoiceHelper.normalizeLabel('doi_tuong'), 'đối tượng');
    });

    test('is case-insensitive', () {
      expect(VoiceHelper.normalizeLabel('BAN'), 'bàn');
      expect(VoiceHelper.normalizeLabel('XE'), 'xe hơi');
      expect(VoiceHelper.normalizeLabel('CAY'), 'cây');
    });

    test('trims whitespace', () {
      expect(VoiceHelper.normalizeLabel('  xe  '), 'xe hơi');
      expect(VoiceHelper.normalizeLabel('\tghe\n'), 'ghế');
    });

    test('returns "vật thể" for empty string', () {
      expect(VoiceHelper.normalizeLabel(''), 'vật thể');
    });

    test('returns "vật thể" for whitespace-only string', () {
      expect(VoiceHelper.normalizeLabel('   '), 'vật thể');
    });

    test('replaces underscores for unknown labels', () {
      expect(VoiceHelper.normalizeLabel('fire_hydrant'), 'fire hydrant');
    });

    test('returns unknown label as-is (no underscores)', () {
      expect(VoiceHelper.normalizeLabel('sofa'), 'sofa');
    });
  });

  group('buildWarning', () {
    test('builds full warning sentence', () {
      final result = VoiceHelper.buildWarning(
        label: 'xe',
        position: 'bên trái',
        distance: 'gần',
      );
      expect(result, 'Cảnh báo! xe hơi ở bên trái, gần.');
    });

    test('handles unknown labels in warning', () {
      final result = VoiceHelper.buildWarning(
        label: 'nguoi_di_bo',
        position: 'phía trước',
        distance: 'xa',
      );
      expect(result, 'Cảnh báo! người đi bộ ở phía trước, xa.');
    });
  });

  group('static message methods', () {
    test('modelLoaded returns system ready message', () {
      expect(VoiceHelper.modelLoaded(), 'Hệ thống sẵn sàng');
    });

    test('noObjectFound returns no object message', () {
      expect(VoiceHelper.noObjectFound(), 'Không phát hiện vật thể');
    });

    test('systemError returns error message', () {
      expect(
        VoiceHelper.systemError(),
        'Lỗi hệ thống, vui lòng thử lại',
      );
    });
  });
}
