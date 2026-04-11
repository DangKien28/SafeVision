import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safe_vision_app/features/detection/data/datasources/detection_local_datasource.dart';
import 'package:safe_vision_app/features/detection/data/repositories/detection_repository_impl.dart';

class MockDetectionLocalDatasource extends Mock
    implements DetectionLocalDatasource {}

class FakeCameraImage extends Fake implements CameraImage {}

void main() {
  late MockDetectionLocalDatasource mockDatasource;
  late DetectionRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(FakeCameraImage());
  });

  setUp(() {
    mockDatasource = MockDetectionLocalDatasource();
    repository = DetectionRepositoryImpl(mockDatasource);
  });

  group('loadModel', () {
    test('delegates to datasource', () async {
      when(() => mockDatasource.loadModel()).thenAnswer((_) async {});
      await repository.loadModel();
      verify(() => mockDatasource.loadModel()).called(1);
    });
  });

  group('closeModel', () {
    test('delegates to datasource', () async {
      when(() => mockDatasource.closeModel()).thenAnswer((_) async {});
      await repository.closeModel();
      verify(() => mockDatasource.closeModel()).called(1);
    });
  });

  group('detectFromFrame', () {
    test('converts raw maps to DetectionObject list', () async {
      final rawResults = [
        {
          'label': 'car',
          'confidence': 0.95,
          'left': 0.1,
          'top': 0.2,
          'width': 0.3,
          'height': 0.4,
        },
        {
          'label': 'dog',
          'confidence': 0.80,
          'left': 0.5,
          'top': 0.5,
          'width': 0.2,
          'height': 0.2,
        },
      ];

      when(() => mockDatasource.runInference(
            any(),
            rotationDegrees: any(named: 'rotationDegrees'),
          )).thenAnswer((_) async => rawResults);

      final result = await repository.detectFromFrame(
        FakeCameraImage(),
        rotationDegrees: 90,
      );

      expect(result.length, 2);
      expect(result[0].label, 'car');
      expect(result[0].confidence, 0.95);
      expect(result[0].boundingBox.left, 0.1);
      expect(result[0].boundingBox.top, 0.2);
      expect(result[0].boundingBox.width, 0.3);
      expect(result[0].boundingBox.height, 0.4);
      expect(result[1].label, 'dog');
      expect(result[1].confidence, 0.80);
    });

    test('returns empty list when inference returns nothing', () async {
      when(() => mockDatasource.runInference(
            any(),
            rotationDegrees: any(named: 'rotationDegrees'),
          )).thenAnswer((_) async => []);

      final result = await repository.detectFromFrame(
        FakeCameraImage(),
        rotationDegrees: 0,
      );

      expect(result, isEmpty);
    });
  });
}
