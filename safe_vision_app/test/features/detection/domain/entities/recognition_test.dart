import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/domain/entities/recognition.dart';

void main() {
  const testBox = BoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.4);

  group('Recognition', () {
    test('stores all properties', () {
      const r = Recognition(id: 1, label: 'car', score: 0.9, location: testBox);
      expect(r.id, 1);
      expect(r.label, 'car');
      expect(r.score, 0.9);
      expect(r.location, testBox);
    });

    test('toDetectionObject converts correctly', () {
      const r =
          Recognition(id: 1, label: 'dog', score: 0.85, location: testBox);
      final obj = r.toDetectionObject();
      expect(obj.label, 'dog');
      expect(obj.confidence, 0.85);
      expect(obj.boundingBox, testBox);
    });

    test('Equatable equality', () {
      const r1 =
          Recognition(id: 1, label: 'car', score: 0.9, location: testBox);
      const r2 =
          Recognition(id: 1, label: 'car', score: 0.9, location: testBox);
      const r3 =
          Recognition(id: 2, label: 'car', score: 0.9, location: testBox);
      expect(r1, equals(r2));
      expect(r1, isNot(equals(r3)));
    });

    test('props contains all fields', () {
      const r = Recognition(id: 1, label: 'car', score: 0.9, location: testBox);
      expect(r.props, [1, 'car', 0.9, testBox]);
    });
  });
}
