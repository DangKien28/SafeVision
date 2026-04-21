import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/models/camera_frame.dart';
import 'package:safe_vision_app/features/detection/data/datasources/detection_local_datasource.dart';
import 'package:safe_vision_app/features/detection/data/datasources/hybrid_detection_local_datasource_impl.dart';

class _FakeDatasource implements DetectionLocalDatasource {
  _FakeDatasource({
    this.results = const [],
    this.throwOnRun = false,
  });

  final List<Map<String, dynamic>> results;
  final bool throwOnRun;
  int loadCount = 0;
  int runCount = 0;
  int closeCount = 0;

  @override
  Future<void> closeModel() async {
    closeCount++;
  }

  @override
  Future<void> loadModel() async {
    loadCount++;
  }

  @override
  Future<List<Map<String, dynamic>>> runInference(
    CameraFrame frame, {
    required int rotationDegrees,
  }) async {
    runCount++;
    if (throwOnRun) throw Exception('run failed');
    return results;
  }
}

CameraFrame _fakeFrame() => CameraFrame(
      planes: [
        Uint8List.fromList(List<int>.filled(16, 128)),
        Uint8List.fromList(List<int>.filled(4, 64)),
        Uint8List.fromList(List<int>.filled(4, 64)),
      ],
      rowStrides: [4, 2, 2],
      pixelStrides: [1, 1, 1],
      width: 4,
      height: 4,
    );

void main() {
  group('HybridDetectionLocalDatasourceImpl', () {
    test('uses primary results when primary is non-empty', () async {
      final primary = _FakeDatasource(
        results: const [
          {
            'label': 'car',
            'confidence': 0.9,
            'left': 0,
            'top': 0,
            'width': 1,
            'height': 1
          },
        ],
      );
      final fallback = _FakeDatasource(
        results: const [
          {
            'label': 'person',
            'confidence': 0.8,
            'left': 0,
            'top': 0,
            'width': 1,
            'height': 1
          },
        ],
      );

      final hybrid = HybridDetectionLocalDatasourceImpl(
        primaryDatasource: primary,
        fallbackDatasource: fallback,
        enableFallback: true,
        fallbackIntervalFrames: 1,
      );
      await hybrid.loadModel();

      final result =
          await hybrid.runInference(_fakeFrame(), rotationDegrees: 90);

      expect(result.first['label'], 'car');
      expect(primary.runCount, 1);
      expect(fallback.runCount, 0);
    });

    test('uses fallback when primary empty and interval condition is met',
        () async {
      final primary = _FakeDatasource(results: const []);
      final fallback = _FakeDatasource(
        results: const [
          {
            'label': 'person',
            'confidence': 0.8,
            'left': 0,
            'top': 0,
            'width': 1,
            'height': 1
          },
        ],
      );

      final hybrid = HybridDetectionLocalDatasourceImpl(
        primaryDatasource: primary,
        fallbackDatasource: fallback,
        enableFallback: true,
        fallbackIntervalFrames: 2,
      );
      await hybrid.loadModel();

      final first =
          await hybrid.runInference(_fakeFrame(), rotationDegrees: 90);
      final second =
          await hybrid.runInference(_fakeFrame(), rotationDegrees: 90);

      expect(first, isEmpty);
      expect(second.first['label'], 'person');
      expect(fallback.runCount, 1);
    });

    test('falls back when primary throws', () async {
      final primary = _FakeDatasource(throwOnRun: true);
      final fallback = _FakeDatasource(
        results: const [
          {
            'label': 'bag',
            'confidence': 0.7,
            'left': 0,
            'top': 0,
            'width': 1,
            'height': 1
          },
        ],
      );

      final hybrid = HybridDetectionLocalDatasourceImpl(
        primaryDatasource: primary,
        fallbackDatasource: fallback,
        enableFallback: true,
        fallbackIntervalFrames: 3,
      );
      await hybrid.loadModel();

      final result =
          await hybrid.runInference(_fakeFrame(), rotationDegrees: 90);

      expect(result.first['label'], 'bag');
      expect(fallback.runCount, 1);
    });
  });
}
