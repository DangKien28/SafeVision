import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/config/detection_config.dart';
import 'package:safe_vision_app/core/models/camera_frame.dart';
import 'package:safe_vision_app/features/detection/data/datasources/mlkit_detection_local_datasource_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The ML Kit Flutter plugin routes all ObjectDetector operations through
  // the 'google_mlkit_object_detector' MethodChannel.  The relevant methods:
  //
  //   vision#startObjectDetector  — called by ObjectDetector.processImage()
  //                                  (one call per runInference invocation)
  //   vision#closeObjectDetector  — called by ObjectDetector.close()
  //
  // Note: despite the name, 'vision#startObjectDetector' does NOT correspond
  // to creating the detector; it is the inference call.  The detector is
  // identified by a stable 'id' argument that stays the same across multiple
  // processImage calls as long as the same ObjectDetector instance is used.
  const channel = MethodChannel('google_mlkit_object_detector');
  final calls = <MethodCall>[];
  Future<dynamic> Function(MethodCall call)? channelHandler;

  CameraFrame frame({
    List<List<int>>? planes,
    int width = 4,
    int height = 4,
    List<int>? rowStrides,
  }) =>
      CameraFrame(
        planes: (planes ??
                const <List<int>>[
                  <int>[1, 2, 3, 4],
                  <int>[5, 6],
                  <int>[7, 8],
                ])
            .map(Uint8List.fromList)
            .toList(growable: false),
        rowStrides: rowStrides ?? const <int>[4, 2, 2],
        pixelStrides: const <int>[1, 1, 1],
        width: width,
        height: height,
      );

  setUp(() {
    calls.clear();
    channelHandler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return channelHandler?.call(call);
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('MlKitDetectionLocalDatasourceImpl', () {
    // Verifies that calling loadModel() twice does NOT create a second
    // ObjectDetector.  The guard `if (_detector != null) return` ensures
    // idempotency.
    //
    // How the assertion works:
    //  - 'vision#startObjectDetector' is the channel method for processImage().
    //    It is called once per runInference() invocation, not per loadModel().
    //  - Two runInference() calls → two 'vision#startObjectDetector' calls.
    //  - Both calls carry the same detector 'id' (id1 == id2) because the
    //    same ObjectDetector instance is reused after the second loadModel()
    //    call returned early.
    //  - One 'vision#closeObjectDetector' call after closeModel().
    test('loadModel is idempotent and keeps same detector instance', () async {
      channelHandler = (call) async {
        if (call.method == 'vision#startObjectDetector') return <dynamic>[];
        return null;
      };

      final datasource = MlKitDetectionLocalDatasourceImpl(DetectionConfig());
      await datasource.loadModel();
      await datasource.runInference(frame(), rotationDegrees: 0);
      await datasource.loadModel(); // guard fires — detector is NOT recreated
      await datasource.runInference(frame(), rotationDegrees: 90);
      await datasource.closeModel();

      // Two runInference() calls → two processImage() channel calls.
      final startCalls =
          calls.where((c) => c.method == 'vision#startObjectDetector').toList();
      final closeCalls =
          calls.where((c) => c.method == 'vision#closeObjectDetector').toList();

      expect(
        startCalls,
        hasLength(2),
        reason: 'vision#startObjectDetector is the processImage channel call; '
            'one call per runInference invocation, so two calls total.',
      );
      expect(closeCalls, hasLength(1));

      // The detector 'id' embedded in each call must be identical, proving
      // that the same ObjectDetector instance was used for both inferences.
      final id1 = (startCalls[0].arguments as Map<dynamic, dynamic>)['id'];
      final id2 = (startCalls[1].arguments as Map<dynamic, dynamic>)['id'];
      final closedId =
          (closeCalls.single.arguments as Map<dynamic, dynamic>)['id'];
      expect(id1, id2,
          reason: 'Same detector id proves loadModel() did not create a '
              'second ObjectDetector on its second invocation');
      expect(closedId, id1,
          reason:
              'The closed detector must be the same one used for inference');
    });

    test('converts frame to input bytes and maps rotation metadata', () async {
      Map<dynamic, dynamic>? capturedImageData;
      channelHandler = (call) async {
        if (call.method == 'vision#startObjectDetector') {
          final args = call.arguments as Map<dynamic, dynamic>;
          capturedImageData = args['imageData'] as Map<dynamic, dynamic>;
          return <dynamic>[];
        }
        return null;
      };

      final datasource = MlKitDetectionLocalDatasourceImpl(DetectionConfig());
      await datasource.loadModel();
      await datasource.runInference(
        frame(
          planes: const <List<int>>[
            <int>[10, 11, 12],
            <int>[13, 14],
            <int>[15],
          ],
          width: 3,
          height: 2,
          rowStrides: const <int>[3, 2, 1],
        ),
        rotationDegrees: 270,
      );
      await datasource.closeModel();

      expect(capturedImageData, isNotNull);
      final bytes = capturedImageData!['bytes'] as Uint8List;
      final metadata = capturedImageData!['metadata'] as Map<dynamic, dynamic>;

      // Planes are concatenated in order: Y + U + V.
      expect(bytes, orderedEquals(<int>[10, 11, 12, 13, 14, 15]));
      expect(metadata['rotation'], 270);
      expect(metadata['width'], 3.0);
      expect(metadata['height'], 2.0);
      expect(metadata['bytes_per_row'], 3);
    });

    test('maps labels, applies confidence filter, and respects max detections',
        () async {
      channelHandler = (call) async {
        if (call.method == 'vision#startObjectDetector') {
          return <dynamic>[
            // Object 1: two labels; 'xe' has higher confidence → wins.
            <String, dynamic>{
              'trackingId': 1,
              'rect': <String, dynamic>{
                'left': 0,
                'top': 0,
                'right': 50,
                'bottom': 50,
              },
              'labels': <Map<String, dynamic>>[
                <String, dynamic>{'confidence': 0.2, 'index': 0, 'text': 'ban'},
                <String, dynamic>{'confidence': 0.7, 'index': 1, 'text': 'xe'},
              ],
            },
            // Object 2: no labels → falls back to _unknownLabel ('doi_tuong')
            // with synthetic confidence 0.5.  Passes the 0.45 threshold.
            <String, dynamic>{
              'trackingId': 2,
              'rect': <String, dynamic>{
                'left': 10,
                'top': 10,
                'right': 60,
                'bottom': 60,
              },
              'labels': <Map<String, dynamic>>[],
            },
            // Object 3: confidence 0.4 < threshold 0.45 → filtered out.
            <String, dynamic>{
              'trackingId': 3,
              'rect': <String, dynamic>{
                'left': 20,
                'top': 20,
                'right': 70,
                'bottom': 70,
              },
              'labels': <Map<String, dynamic>>[
                <String, dynamic>{'confidence': 0.4, 'index': 2, 'text': 'cay'},
              ],
            },
          ];
        }
        return null;
      };

      final datasource = MlKitDetectionLocalDatasourceImpl(
        DetectionConfig(confidenceThreshold: 0.45, maxDetections: 2),
      );
      await datasource.loadModel();

      final results = await datasource.runInference(
        frame(width: 100, height: 100),
        rotationDegrees: 0,
      );

      await datasource.closeModel();

      // Object 3 (confidence 0.4) is filtered; 2 results remain.
      expect(results, hasLength(2));

      // Results are sorted by confidence descending.
      expect(results[0]['label'], 'xe');
      expect(results[0]['confidence'], 0.7);
      expect(results[0]['left'], 0.0);
      expect(results[0]['width'], 0.5);

      // Object 2 has no labels → 'doi_tuong' with synthetic confidence 0.5.
      expect(results[1]['label'], 'doi_tuong');
      expect(results[1]['confidence'], 0.5);
    });

    test('runInference returns empty list when _isBusy', () async {
      // Simulates a slow inference to hold _isBusy = true while a second
      // runInference call arrives.
      var inferenceStarted = false;
      var inferenceCompleted = false;

      channelHandler = (call) async {
        if (call.method == 'vision#startObjectDetector') {
          inferenceStarted = true;
          // Yield to allow concurrent code to run.
          await Future<void>.delayed(const Duration(milliseconds: 30));
          inferenceCompleted = true;
          return <dynamic>[];
        }
        return null;
      };

      final datasource = MlKitDetectionLocalDatasourceImpl(DetectionConfig());
      await datasource.loadModel();

      // Start a slow inference and immediately call runInference again.
      final firstFuture = datasource.runInference(frame(), rotationDegrees: 0);
      // Let the first call get as far as setting _isBusy = true.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(inferenceStarted, isTrue);
      expect(inferenceCompleted, isFalse);

      // Second call arrives while first is still running → must return [].
      final secondResult =
          await datasource.runInference(frame(), rotationDegrees: 0);
      expect(secondResult, isEmpty,
          reason: '_isBusy guard must cause the second call to return []');

      await firstFuture; // drain
      await datasource.closeModel();
    });

    test('closeModel resets _isBusy and allows subsequent inference', () async {
      channelHandler = (call) async {
        if (call.method == 'vision#startObjectDetector') return <dynamic>[];
        return null;
      };

      final datasource = MlKitDetectionLocalDatasourceImpl(DetectionConfig());
      await datasource.loadModel();
      await datasource.closeModel();

      // After close, the detector is null → runInference must return [].
      final result = await datasource.runInference(frame(), rotationDegrees: 0);
      expect(result, isEmpty,
          reason:
              'runInference must return [] when detector is null after close');
    });
  });
}
