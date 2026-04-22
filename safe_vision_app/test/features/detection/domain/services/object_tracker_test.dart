import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/domain/entities/tracked_detection.dart';
import 'package:safe_vision_app/features/detection/domain/services/object_tracker.dart';

DetectionObject _makeDetection({
  String label = 'laptop',
  double left = 0.20,
  double top = 0.20,
  double width = 0.24,
  double height = 0.18,
  double confidence = 0.9,
}) {
  return DetectionObject(
    label: label,
    confidence: confidence,
    boundingBox: BoundingBox(
      left: left,
      top: top,
      width: width,
      height: height,
    ),
  );
}

void main() {
  group('ObjectTracker', () {
    test('track mới bắt đầu ở tentative rồi chuyển sang active khi đủ confirm',
        () {
      final tracker = ObjectTracker();

      final first = tracker.update([_makeDetection()]);
      expect(first, hasLength(1));
      expect(first.first.phase, TrackedDetectionPhase.tentative);

      final second = tracker.update([_makeDetection(left: 0.205, top: 0.205)]);
      expect(second, hasLength(1));
      expect(second.first.trackId, first.first.trackId);
      expect(second.first.phase, TrackedDetectionPhase.active);
      expect(second.first.consecutiveVisibleFrames, greaterThanOrEqualTo(2));
    });

    test('track active được giữ ở trạng thái fading thay vì biến mất ngay', () {
      final tracker = ObjectTracker();

      tracker.update([_makeDetection()]);
      final active = tracker.update([_makeDetection(left: 0.205, top: 0.205)]);
      expect(active.single.phase, TrackedDetectionPhase.active);

      final fading = tracker.update(const []);
      expect(fading, hasLength(1));
      expect(fading.single.trackId, active.single.trackId);
      expect(fading.single.phase, TrackedDetectionPhase.fading);
      expect(fading.single.missedFrames, 1);
    });

    test(
        'track fading có thể reacquire lại cùng trackId khi vật thể xuất hiện gần đó',
        () {
      final tracker = ObjectTracker();

      tracker.update([_makeDetection()]);
      final active = tracker.update([_makeDetection(left: 0.205, top: 0.205)]);
      final fading = tracker.update(const []);

      final recovered = tracker.update([
        _makeDetection(left: 0.215, top: 0.21, width: 0.25, height: 0.19),
      ]);

      expect(fading.single.phase, TrackedDetectionPhase.fading);
      expect(recovered, hasLength(1));
      expect(recovered.single.trackId, active.single.trackId);
      expect(recovered.single.phase, TrackedDetectionPhase.active);
      expect(recovered.single.missedFrames, 0);
    });

    test('tentative noise bị loại bỏ nhanh nếu mất ngay ở frame kế tiếp', () {
      final tracker = ObjectTracker();

      final first = tracker.update([_makeDetection()]);
      expect(first.single.phase, TrackedDetectionPhase.tentative);

      final second = tracker.update(const []);
      expect(second, isEmpty);
    });
  });
}
