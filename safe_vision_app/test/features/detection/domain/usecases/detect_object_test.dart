import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/core/usecases/usecase.dart';
import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/domain/repositories/detection_repository.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/detection_object_from_frame.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/load_model_usecase.dart';

class MockDetectionRepository extends Mock implements DetectionRepository {}

class MockCameraImage extends Mock implements CameraImage {}

DetectionObject _makeDetection({
  String label = 'person',
  double confidence = 0.85,
  double left = 0.1,
  double top = 0.1,
  double width = 0.3,
  double height = 0.4,
}) =>
    DetectionObject(
      label: label,
      confidence: confidence,
      boundingBox: BoundingBox(
        left: left,
        top: top,
        width: width,
        height: height,
      ),
    );

void main() {
  late MockDetectionRepository mockRepository;
  late MockCameraImage mockImage;

  setUpAll(() {
    registerFallbackValue(MockCameraImage());
    registerFallbackValue(const NoParams());
  });

  setUp(() {
    mockRepository = MockDetectionRepository();
    mockImage = MockCameraImage();
  });

  group('DetectionObjectFromFrame', () {
    late DetectionObjectFromFrame usecase;

    setUp(() {
      usecase = DetectionObjectFromFrame(mockRepository);
    });

    test('calls repository.detectFromFrame with provided image', () async {
      when(() => mockRepository.detectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => []);

      await usecase(mockImage, rotationDegrees: 90);

      verify(() =>
              mockRepository.detectFromFrame(mockImage, rotationDegrees: 90))
          .called(1);
    });

    test('returns list of DetectionObject from repository', () async {
      final expected = [
        _makeDetection(label: 'person', confidence: 0.9),
        _makeDetection(label: 'bicycle', confidence: 0.7),
      ];
      when(() => mockRepository.detectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => expected);

      final result = await usecase(mockImage, rotationDegrees: 90);

      expect(result, equals(expected));
      expect(result.length, 2);
      expect(result[0].label, 'person');
      expect(result[1].label, 'bicycle');
    });

    test('returns empty list when no objects are detected', () async {
      when(() => mockRepository.detectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => []);

      final result = await usecase(mockImage, rotationDegrees: 90);

      expect(result, isEmpty);
    });

    test('rethrows exception from repository', () async {
      when(() => mockRepository.detectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenThrow(Exception('Inference failed'));

      expect(() => usecase(mockImage, rotationDegrees: 90), throwsException);
    });

    test('calls repository exactly once per call', () async {
      when(() => mockRepository.detectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => []);

      await usecase(mockImage, rotationDegrees: 90);
      await usecase(mockImage, rotationDegrees: 90);

      verify(() =>
              mockRepository.detectFromFrame(mockImage, rotationDegrees: 90))
          .called(2);
    });
  });

  group('LoadModelUsecase', () {
    late LoadModelUsecase usecase;

    setUp(() {
      usecase = LoadModelUsecase(mockRepository);
    });

    test('call(NoParams()) forwards to repository.loadModel()', () async {
      when(() => mockRepository.loadModel()).thenAnswer((_) async {});

      await usecase.call(const NoParams());

      verify(() => mockRepository.loadModel()).called(1);
    });

    test('call(NoParams()) actually calls repository.loadModel()', () async {
      when(() => mockRepository.loadModel()).thenAnswer((_) async {});

      await usecase.call(const NoParams());

      verify(() => mockRepository.loadModel()).called(1);
    });

    test('call(NoParams()) rethrows exception on failure', () async {
      when(() => mockRepository.loadModel())
          .thenThrow(Exception('Model file not found'));

      expect(() => usecase.call(const NoParams()), throwsException);
    });

    test('implements UseCase<void, NoParams>', () {
      expect(usecase, isA<UseCase<void, NoParams>>());
    });

    test('does not call detectFromFrame', () async {
      when(() => mockRepository.loadModel()).thenAnswer((_) async {});

      await usecase.call(const NoParams());

      verifyNever(() => mockRepository.detectFromFrame(any(),
          rotationDegrees: any(named: 'rotationDegrees')));
    });
  });

  group('DetectionObject', () {
    test(
        'voiceWarning translates label to Vietnamese and concatenates position and distance',
        () {
      final obj = _makeDetection(
        label: 'person',
        left: 0.1,
        top: 0.1,
        width: 0.4,
        height: 0.4,
      );

      expect(obj.voiceWarning, contains('người đi bộ'));
    });

    test('isDangerous is true when area > 0.10', () {
      final dangerous = _makeDetection(width: 0.4, height: 0.4);
      expect(dangerous.isDangerous, isTrue);
    });

    test('isDangerous is false when area <= 0.10', () {
      final safe = _makeDetection(width: 0.2, height: 0.4);
      expect(safe.isDangerous, isFalse);
    });
  });

  group('BoundingBox', () {
    test('right = left + width', () {
      const box = BoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.4);
      expect(box.right, closeTo(0.4, 1e-9));
    });

    test('bottom = top + height', () {
      const box = BoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.4);
      expect(box.bottom, closeTo(0.6, 1e-9));
    });

    test('centerX = left + width/2', () {
      const box = BoundingBox(left: 0.1, top: 0.0, width: 0.4, height: 0.0);
      expect(box.centerX, closeTo(0.3, 1e-9));
    });

    test('centerY = top + height/2', () {
      const box = BoundingBox(left: 0.0, top: 0.2, width: 0.0, height: 0.4);
      expect(box.centerY, closeTo(0.4, 1e-9));
    });

    test('area = width * height', () {
      const box = BoundingBox(left: 0.0, top: 0.0, width: 0.3, height: 0.5);
      expect(box.area, closeTo(0.15, 1e-9));
    });

    group('horizontalPosition', () {
      test('returns "bên trái" when centerX < 0.33', () {
        const box = BoundingBox(left: 0.0, top: 0.0, width: 0.2, height: 0.1);
        expect(box.horizontalPosition, 'bên trái');
      });

      test('returns "bên phải" when centerX > 0.67', () {
        const box = BoundingBox(left: 0.8, top: 0.0, width: 0.2, height: 0.1);
        expect(box.horizontalPosition, 'bên phải');
      });

      test('returns "phía trước" when centerX is in [0.33, 0.67]', () {
        const box = BoundingBox(left: 0.4, top: 0.0, width: 0.2, height: 0.1);
        expect(box.horizontalPosition, 'phía trước');
      });
    });

    group('proximityLabel', () {
      test('returns "rất gần" when area > 0.25', () {
        const box = BoundingBox(left: 0.0, top: 0.0, width: 0.6, height: 0.5);
        expect(box.proximityLabel, 'rất gần');
      });

      test('returns "gần" when area is in (0.10, 0.25]', () {
        const box = BoundingBox(left: 0.0, top: 0.0, width: 0.4, height: 0.4);
        expect(box.proximityLabel, 'gần');
      });

      test('returns "khoảng cách trung bình" when area is in (0.03, 0.10]', () {
        const box = BoundingBox(left: 0.0, top: 0.0, width: 0.2, height: 0.3);
        expect(box.proximityLabel, 'khoảng cách trung bình');
      });

      test('returns "xa" when area <= 0.03', () {
        const box = BoundingBox(left: 0.0, top: 0.0, width: 0.1, height: 0.1);
        expect(box.proximityLabel, 'xa');
      });
    });

    test('equality comparison relies on all four fields', () {
      const a = BoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.4);
      const b = BoundingBox(left: 0.1, top: 0.2, width: 0.3, height: 0.4);
      const c = BoundingBox(left: 0.9, top: 0.2, width: 0.3, height: 0.4);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
