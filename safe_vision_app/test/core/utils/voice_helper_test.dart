import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/utils/voice_helper.dart';

void main() {
  group('normalizeLabel', () {
    test('maps known English labels to Vietnamese', () {
      expect(VoiceHelper.normalizeLabel('car'), 'xe hơi');
      expect(VoiceHelper.normalizeLabel('dog'), 'chó');
      expect(VoiceHelper.normalizeLabel('cat'), 'mèo');
      expect(VoiceHelper.normalizeLabel('person'), 'người đi bộ');
      expect(VoiceHelper.normalizeLabel('bicycle'), 'xe đạp');
      expect(VoiceHelper.normalizeLabel('bus'), 'xe buýt');
      expect(VoiceHelper.normalizeLabel('truck'), 'xe tải');
      expect(VoiceHelper.normalizeLabel('motorbike'), 'xe máy');
      expect(VoiceHelper.normalizeLabel('motorcycle'), 'xe máy');
      expect(VoiceHelper.normalizeLabel('chair'), 'ghế');
      expect(VoiceHelper.normalizeLabel('table'), 'bàn');
      expect(VoiceHelper.normalizeLabel('tree'), 'cây');
      expect(VoiceHelper.normalizeLabel('phone'), 'điện thoại');
      expect(VoiceHelper.normalizeLabel('stair'), 'cầu thang');
      expect(VoiceHelper.normalizeLabel('stairs'), 'cầu thang');
    });

    test('maps known Vietnamese labels', () {
      expect(VoiceHelper.normalizeLabel('ban'), 'bàn');
      expect(VoiceHelper.normalizeLabel('ghe'), 'ghế');
      expect(VoiceHelper.normalizeLabel('cau_thang'), 'cầu thang');
      expect(VoiceHelper.normalizeLabel('nguoi_di_bo'), 'người đi bộ');
      expect(VoiceHelper.normalizeLabel('xe'), 'xe');
      expect(VoiceHelper.normalizeLabel('pedestrian'), 'người đi bộ');
    });

    test('is case-insensitive', () {
      expect(VoiceHelper.normalizeLabel('Car'), 'xe hơi');
      expect(VoiceHelper.normalizeLabel('DOG'), 'chó');
      expect(VoiceHelper.normalizeLabel('Person'), 'người đi bộ');
    });

    test('trims whitespace', () {
      expect(VoiceHelper.normalizeLabel('  car  '), 'xe hơi');
      expect(VoiceHelper.normalizeLabel('\tdog\n'), 'chó');
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
        label: 'car',
        position: 'bên trái',
        distance: 'gần',
      );
      expect(result, 'Cảnh báo! xe hơi ở bên trái, gần.');
    });

    test('handles unknown labels in warning', () {
      final result = VoiceHelper.buildWarning(
        label: 'sofa',
        position: 'phía trước',
        distance: 'xa',
      );
      expect(result, 'Cảnh báo! sofa ở phía trước, xa.');
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
