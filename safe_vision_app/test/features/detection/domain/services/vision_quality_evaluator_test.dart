import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/models/camera_frame.dart';
import 'package:safe_vision_app/features/detection/domain/services/vision_quality_evaluator.dart';

CameraFrame _frameWithYPlane(Uint8List yPlane) => CameraFrame(
      planes: [yPlane, Uint8List(8), Uint8List(8)],
      rowStrides: [8, 4, 4],
      pixelStrides: [1, 2, 2],
      width: 8,
      height: 8,
    );

void main() {
  group('VisionQualityEvaluator', () {
    test('returns low score for empty frame', () {
      final frame = CameraFrame(
        planes: [Uint8List(0), Uint8List(0), Uint8List(0)],
        rowStrides: [0, 0, 0],
        pixelStrides: [1, 1, 1],
        width: 0,
        height: 0,
      );

      expect(VisionQualityEvaluator.score(frame), 0);
    });

    test('returns better score for balanced brightness', () {
      final dark = _frameWithYPlane(Uint8List.fromList(List.filled(128, 15)));
      final balanced =
          _frameWithYPlane(Uint8List.fromList(List.filled(128, 128)));

      expect(
        VisionQualityEvaluator.score(balanced),
        greaterThan(VisionQualityEvaluator.score(dark)),
      );
    });
  });
}
