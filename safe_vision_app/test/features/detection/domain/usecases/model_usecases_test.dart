import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safe_vision_app/core/usecases/usecase.dart';
import 'package:safe_vision_app/features/detection/domain/repositories/detection_repository.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/close_model_usecase.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/load_model_usecase.dart';

class MockDetectionRepository extends Mock implements DetectionRepository {}

void main() {
  late MockDetectionRepository mockRepo;

  setUp(() {
    mockRepo = MockDetectionRepository();
  });

  group('LoadModelUsecase', () {
    late LoadModelUsecase usecase;

    setUp(() {
      usecase = LoadModelUsecase(mockRepo);
    });

    test('delegates to repository.loadModel', () async {
      when(() => mockRepo.loadModel()).thenAnswer((_) async {});
      await usecase(const NoParams());
      verify(() => mockRepo.loadModel()).called(1);
    });

    test('propagates exceptions from repository', () async {
      when(() => mockRepo.loadModel()).thenThrow(Exception('load failed'));
      expect(
        () => usecase(const NoParams()),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CloseModelUsecase', () {
    late CloseModelUsecase usecase;

    setUp(() {
      usecase = CloseModelUsecase(mockRepo);
    });

    test('delegates to repository.closeModel', () async {
      when(() => mockRepo.closeModel()).thenAnswer((_) async {});
      await usecase(const NoParams());
      verify(() => mockRepo.closeModel()).called(1);
    });

    test('propagates exceptions from repository', () async {
      when(() => mockRepo.closeModel()).thenThrow(Exception('close failed'));
      expect(
        () => usecase(const NoParams()),
        throwsA(isA<Exception>()),
      );
    });
  });
}
