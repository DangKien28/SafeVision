import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/error/exceptions.dart';

void main() {
  group('ModelNotFoundException', () {
    test('stores message', () {
      const e = ModelNotFoundException('model not found');
      expect(e.message, 'model not found');
    });

    test('toString contains class name and message', () {
      const e = ModelNotFoundException('missing file');
      expect(e.toString(), 'ModelNotFoundException: missing file');
    });
  });

  group('InferenceException', () {
    test('stores message', () {
      const e = InferenceException('inference failed');
      expect(e.message, 'inference failed');
    });

    test('toString contains class name and message', () {
      const e = InferenceException('timeout');
      expect(e.toString(), 'InferenceException: timeout');
    });
  });

  group('CameraException', () {
    test('stores message', () {
      const e = CameraException('camera error');
      expect(e.message, 'camera error');
    });

    test('toString contains class name and message', () {
      const e = CameraException('not available');
      expect(e.toString(), 'CameraException: not available');
    });
  });

  group('PermissionException', () {
    test('stores message', () {
      const e = PermissionException('denied');
      expect(e.message, 'denied');
    });

    test('toString contains class name and message', () {
      const e = PermissionException('camera denied');
      expect(e.toString(), 'PermissionException: camera denied');
    });
  });

  group('ImageConversionException', () {
    test('stores message', () {
      const e = ImageConversionException('conversion failed');
      expect(e.message, 'conversion failed');
    });

    test('toString contains class name and message', () {
      const e = ImageConversionException('invalid format');
      expect(e.toString(), 'ImageConversionException: invalid format');
    });
  });
}
