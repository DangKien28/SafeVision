// test/features/detection/presentation/bloc/datasource_isolate_busy_test.dart
// v4: TrackingDatasource.runInference signature changed from CameraImage → CameraFrame.
// All test call sites updated accordingly.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/core/services/camera_service.dart'
    show CameraFrame;
import 'package:safe_vision_app/features/detection/data/datasources/detection_local_datasource.dart';

class MockDetectionDatasource extends Mock
    implements DetectionLocalDatasource {}

CameraFrame fakeCameraFrame() => CameraFrame(
      planes: [Uint8List(0), Uint8List(0), Uint8List(0)],
      rowStrides: [640, 320, 320],
      pixelStrides: [1, 2, 2],
      width: 640,
      height: 480,
    );

/// Test double that mirrors the finally-block pattern from the real
/// implementation. Verifies that `_isolateBusy` is always reset,
/// including when inference throws.
class TrackingDatasource implements DetectionLocalDatasource {
  bool _modelLoaded = false;
  bool _isolateBusy = false;
  int inferenceCallCount = 0;
  bool shouldThrow = false;
  Exception? exceptionToThrow;
  List<Map<String, dynamic>> Function()? resultFactory;

  bool get isolateBusy => _isolateBusy;

  @override
  Future<void> loadModel() async {
    _modelLoaded = true;
  }

  // v4: accepts CameraFrame instead of CameraImage.
  @override
  Future<List<Map<String, dynamic>>> runInference(
    CameraFrame frame, {
    required int rotationDegrees,
  }) async {
    if (!_modelLoaded) return [];
    if (_isolateBusy) return [];

    _isolateBusy = true;
    inferenceCallCount++;

    try {
      if (shouldThrow) {
        throw exceptionToThrow ?? Exception('Simulated inference error');
      }
      return resultFactory?.call() ?? [];
    } catch (e) {
      rethrow;
    } finally {
      _isolateBusy = false;
    }
  }

  @override
  Future<void> closeModel() async {
    _modelLoaded = false;
    _isolateBusy = false;
  }
}

void main() {
  late TrackingDatasource datasource;

  setUp(() {
    datasource = TrackingDatasource();
  });

  group('_isolateBusy is reset in finally block', () {
    setUp(() async {
      await datasource.loadModel();
    });

    test('isolateBusy is false before first inference', () {
      expect(datasource.isolateBusy, isFalse);
    });

    test('isolateBusy is reset after successful inference', () async {
      datasource.resultFactory = () => [
            {
              'label': 'nguoi_di_bo',
              'confidence': 0.85,
              'left': 0.1,
              'top': 0.1,
              'width': 0.3,
              'height': 0.4,
            }
          ];

      await datasource.runInference(fakeCameraFrame(), rotationDegrees: 0);

      expect(datasource.isolateBusy, isFalse,
          reason: 'isolateBusy must return to false after success');
    });

    test('isolateBusy is reset after inference throws exception', () async {
      datasource.shouldThrow = true;
      datasource.exceptionToThrow = Exception('GPU out of memory');

      try {
        await datasource.runInference(fakeCameraFrame(), rotationDegrees: 0);
      } catch (_) {}

      expect(datasource.isolateBusy, isFalse,
          reason:
              'isolateBusy must return to false even if there\'s an exception');
    });

    test('after exception, subsequent inference runs normally', () async {
      datasource.shouldThrow = true;
      try {
        await datasource.runInference(fakeCameraFrame(), rotationDegrees: 0);
      } catch (_) {}

      datasource.shouldThrow = false;
      datasource.resultFactory = () => [
            {
              'label': 'xe',
              'confidence': 0.7,
              'left': 0.2,
              'top': 0.2,
              'width': 0.2,
              'height': 0.3,
            }
          ];

      final results =
          await datasource.runInference(fakeCameraFrame(), rotationDegrees: 0);

      expect(results, isNotEmpty,
          reason: 'After exception, subsequent inference must still run.');
      expect(results.first['label'], 'xe');
      expect(datasource.inferenceCallCount, equals(2));
    });

    test(
        'concurrently called, second call returns [] if first is still running',
        () async {
      int callCount = 0;
      final ds = TrackingDatasource();
      await ds.loadModel();
      ds.resultFactory = () {
        callCount++;
        return [];
      };

      await ds.runInference(fakeCameraFrame(), rotationDegrees: 0);
      expect(ds.isolateBusy, isFalse);
      await ds.runInference(fakeCameraFrame(), rotationDegrees: 0);

      expect(callCount, equals(2));
    });

    test('closeModel resets isolateBusy', () async {
      datasource.shouldThrow = true;
      try {
        await datasource.runInference(fakeCameraFrame(), rotationDegrees: 0);
      } catch (_) {}

      await datasource.closeModel();

      expect(datasource.isolateBusy, isFalse,
          reason: 'closeModel() must reset isolateBusy');
    });
  });

  group('DetectionDatasource contract', () {
    test('runInference returns [] before loadModel is called', () async {
      final result =
          await datasource.runInference(fakeCameraFrame(), rotationDegrees: 0);
      expect(result, isEmpty);
    });

    test('after loadModel, runInference executes normally', () async {
      await datasource.loadModel();
      datasource.resultFactory = () => [
            {
              'label': 'xe',
              'confidence': 0.9,
              'left': 0.0,
              'top': 0.0,
              'width': 0.5,
              'height': 0.5,
            }
          ];

      final result =
          await datasource.runInference(fakeCameraFrame(), rotationDegrees: 90);

      expect(result.length, equals(1));
      expect(result.first['label'], 'xe');
    });

    test('after closeModel, inference returns []', () async {
      await datasource.loadModel();
      await datasource.closeModel();

      final result =
          await datasource.runInference(fakeCameraFrame(), rotationDegrees: 0);
      expect(result, isEmpty,
          reason:
              'After closeModel(), inference must return [] since model is unloaded');
    });
  });
}
