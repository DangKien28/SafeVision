import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';

void main() {
  group('BoundingBox', () {
    test('computes right and bottom correctly', () {
      const bb = BoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.4);
      expect(bb.right, closeTo(0.4, 1e-10));
      expect(bb.bottom, closeTo(0.6, 1e-10));
    });

    test('computes center correctly', () {
      const bb = BoundingBox(left: 0.0, top: 0.0, width: 1.0, height: 1.0);
      expect(bb.centerX, 0.5);
      expect(bb.centerY, 0.5);
    });

    test('computes area correctly', () {
      const bb = BoundingBox(left: 0.0, top: 0.0, width: 0.5, height: 0.5);
      expect(bb.area, 0.25);
    });

    group('horizontalPosition', () {
      test('returns "bên trái" when centerX < 0.33', () {
        const bb = BoundingBox(left: 0.0, top: 0.0, width: 0.2, height: 0.2);
        expect(bb.horizontalPosition, 'bên trái');
      });

      test('returns "bên phải" when centerX > 0.67', () {
        const bb = BoundingBox(left: 0.7, top: 0.0, width: 0.2, height: 0.2);
        expect(bb.horizontalPosition, 'bên phải');
      });

      test('returns "phía trước" when centerX is in center zone', () {
        const bb = BoundingBox(left: 0.3, top: 0.0, width: 0.2, height: 0.2);
        expect(bb.horizontalPosition, 'phía trước');
      });

      test('returns "phía trước" when centerX is exactly 0.33', () {
        const bb = BoundingBox(left: 0.23, top: 0.0, width: 0.2, height: 0.2);
        // centerX = 0.23 + 0.1 = 0.33, not < 0.33 → "phía trước"
        expect(bb.horizontalPosition, 'phía trước');
      });

      test('returns "phía trước" when centerX is exactly 0.67', () {
        const bb = BoundingBox(left: 0.57, top: 0.0, width: 0.2, height: 0.2);
        // centerX = 0.57 + 0.1 = 0.67, not > 0.67 → "phía trước"
        expect(bb.horizontalPosition, 'phía trước');
      });
    });

    group('proximityLabel', () {
      test('returns "rất gần" for area > 0.25', () {
        const bb = BoundingBox(left: 0.0, top: 0.0, width: 0.6, height: 0.6);
        expect(bb.proximityLabel, 'rất gần');
      });

      test('returns "gần" for area between 0.10 and 0.25', () {
        const bb = BoundingBox(left: 0.0, top: 0.0, width: 0.4, height: 0.4);
        // area = 0.16
        expect(bb.proximityLabel, 'gần');
      });

      test('returns "khoảng cách trung bình" for area between 0.03 and 0.10',
          () {
        const bb = BoundingBox(left: 0.0, top: 0.0, width: 0.2, height: 0.3);
        // area = 0.06
        expect(bb.proximityLabel, 'khoảng cách trung bình');
      });

      test('returns "xa" for area <= 0.03', () {
        const bb = BoundingBox(left: 0.0, top: 0.0, width: 0.1, height: 0.1);
        // area = 0.01
        expect(bb.proximityLabel, 'xa');
      });
    });

    test('Equatable equality', () {
      const bb1 = BoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.4);
      const bb2 = BoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.4);
      const bb3 = BoundingBox(left: 0.5, top: 0.2, width: 0.3, height: 0.4);
      expect(bb1, equals(bb2));
      expect(bb1, isNot(equals(bb3)));
    });

    test('props contains all four fields', () {
      const bb = BoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.4);
      expect(bb.props, [0.1, 0.2, 0.3, 0.4]);
    });
  });

  group('DetectionObject', () {
    const smallBox = BoundingBox(left: 0.0, top: 0.0, width: 0.1, height: 0.1);
    const largeBox = BoundingBox(left: 0.0, top: 0.0, width: 0.5, height: 0.5);
    const leftBox = BoundingBox(left: 0.0, top: 0.0, width: 0.2, height: 0.2);

    test('stores label, confidence, and boundingBox', () {
      const obj = DetectionObject(
        label: 'car',
        confidence: 0.95,
        boundingBox: smallBox,
      );
      expect(obj.label, 'car');
      expect(obj.confidence, 0.95);
      expect(obj.boundingBox, smallBox);
    });

    test('voiceWarning builds correct sentence', () {
      const obj = DetectionObject(
        label: 'car',
        confidence: 0.95,
        boundingBox: leftBox,
      );
      expect(obj.voiceWarning, contains('xe hơi'));
      expect(obj.voiceWarning, startsWith('Cảnh báo!'));
    });

    test('isDangerous returns true for large area', () {
      const obj = DetectionObject(
        label: 'car',
        confidence: 0.95,
        boundingBox: largeBox,
      );
      expect(obj.isDangerous, isTrue);
    });

    test('isDangerous returns false for small area', () {
      const obj = DetectionObject(
        label: 'car',
        confidence: 0.95,
        boundingBox: smallBox,
      );
      expect(obj.isDangerous, isFalse);
    });

    test('Equatable equality', () {
      const obj1 = DetectionObject(
        label: 'car',
        confidence: 0.95,
        boundingBox: smallBox,
      );
      const obj2 = DetectionObject(
        label: 'car',
        confidence: 0.95,
        boundingBox: smallBox,
      );
      const obj3 = DetectionObject(
        label: 'dog',
        confidence: 0.95,
        boundingBox: smallBox,
      );
      expect(obj1, equals(obj2));
      expect(obj1, isNot(equals(obj3)));
    });

    test('props contains label, confidence, and boundingBox', () {
      const obj = DetectionObject(
        label: 'car',
        confidence: 0.95,
        boundingBox: smallBox,
      );
      expect(obj.props, ['car', 0.95, smallBox]);
    });
  });
}
