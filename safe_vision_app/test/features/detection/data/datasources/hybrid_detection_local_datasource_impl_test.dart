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

    // When the primary throws an exception the fallback is attempted immediately,
    // bypassing the interval check.  This test uses fallbackIntervalFrames: 3
    // (so the interval check alone would NOT trigger on frame 1) to prove that
    // the exception path overrides the interval gate.
    test(
        'falls back immediately when primary throws, regardless of frame interval',
        () async {
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

      // fallbackIntervalFrames: 3 means interval alone would not trigger
      // on the first frame (1 % 3 != 0).  The fallback must fire anyway
      // because the primary threw.
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
      expect(fallback.runCount, 1,
          reason: 'Fallback must be called even though frame 1 % 3 != 0');
    });

    test('does not use fallback when enableFallback is false', () async {
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
        enableFallback: false,
        fallbackIntervalFrames: 1,
      );
      await hybrid.loadModel();

      await hybrid.runInference(_fakeFrame(), rotationDegrees: 90);

      expect(fallback.runCount, 0,
          reason: 'Fallback must not run when enableFallback is false');
    });

    test('closeModel closes both datasources even when enableFallback is false',
        () async {
      // closeModel() is unconditional: both datasources are always closed,
      // even if the fallback was never loaded.  This is safe because
      // closeModel() is a no-op on an unloaded datasource.
      final primary = _FakeDatasource();
      final fallback = _FakeDatasource();

      final hybrid = HybridDetectionLocalDatasourceImpl(
        primaryDatasource: primary,
        fallbackDatasource: fallback,
        enableFallback: false, // fallback never loaded
        fallbackIntervalFrames: 1,
      );
      await hybrid.loadModel();
      await hybrid.closeModel();

      expect(primary.closeCount, 1);
      expect(fallback.closeCount, 1,
          reason:
              'Fallback closeModel() must be called even when enableFallback '
              'is false, because closeModel() is defined as a no-op when '
              'the datasource was not loaded');
    });

    test('resets frame counter on closeModel', () async {
      final primary = _FakeDatasource(results: const []);
      final fallback = _FakeDatasource(
        results: const [
          {
            'label': 'xe',
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
      // Frame 1 — no fallback (1 % 2 != 0)
      await hybrid.runInference(_fakeFrame(), rotationDegrees: 0);
      expect(fallback.runCount, 0);

      await hybrid.closeModel();
      await hybrid.loadModel(); // reset counter to 0

      // Frame 1 after reload — again no fallback (counter reset)
      await hybrid.runInference(_fakeFrame(), rotationDegrees: 0);
      expect(fallback.runCount, 0,
          reason:
              'Frame counter must be reset to 0 after closeModel/loadModel');

      // Frame 2 after reload — fallback fires
      await hybrid.runInference(_fakeFrame(), rotationDegrees: 0);
      expect(fallback.runCount, 1);
    });
  });
}
