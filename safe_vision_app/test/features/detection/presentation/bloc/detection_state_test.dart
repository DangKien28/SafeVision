import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_event.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_state.dart';

void main() {
  group('DetectionState', () {
    test('DetectionInitial equality', () {
      const s1 = DetectionInitial();
      const s2 = DetectionInitial();
      expect(s1, equals(s2));
      expect(s1.props, isEmpty);
    });

    test('DetectionLoading equality', () {
      const s1 = DetectionLoading();
      const s2 = DetectionLoading();
      expect(s1, equals(s2));
    });

    test('DetectionModelReady equality', () {
      const s1 = DetectionModelReady();
      const s2 = DetectionModelReady();
      expect(s1, equals(s2));
    });

    test('DetectionSuccess equality with same detections and timestamp', () {
      const obj = DetectionObject(
        label: 'car',
        confidence: 0.9,
        boundingBox: BoundingBox(left: 0, top: 0, width: 0.1, height: 0.1),
      );
      const s1 = DetectionSuccess(detections: [obj], timestamp: 100);
      const s2 = DetectionSuccess(detections: [obj], timestamp: 100);
      expect(s1, equals(s2));
    });

    test('DetectionSuccess inequality with different timestamp', () {
      const s1 = DetectionSuccess(detections: [], timestamp: 100);
      const s2 = DetectionSuccess(detections: [], timestamp: 200);
      expect(s1, isNot(equals(s2)));
    });

    test('DetectionFailure equality', () {
      const s1 = DetectionFailure('error');
      const s2 = DetectionFailure('error');
      const s3 = DetectionFailure('other');
      expect(s1, equals(s2));
      expect(s1, isNot(equals(s3)));
      expect(s1.message, 'error');
    });
  });

  group('DetectionEvent', () {
    test('DetectionStarted equality', () {
      const e1 = DetectionStarted();
      const e2 = DetectionStarted();
      expect(e1, equals(e2));
    });

    test('DetectionStopped equality', () {
      const e1 = DetectionStopped();
      const e2 = DetectionStopped();
      expect(e1, equals(e2));
    });
  });
}
