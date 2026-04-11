import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safe_vision_app/features/tts/data/datasources/tts_service.dart';
import 'package:safe_vision_app/features/tts/data/repositories/tts_repository_impl.dart';

class MockTtsService extends Mock implements TtsService {}

void main() {
  late MockTtsService mockService;
  late TtsRepositoryImpl repository;

  setUp(() {
    mockService = MockTtsService();
    repository = TtsRepositoryImpl(mockService);
  });

  group('initialize', () {
    test('delegates to service.initialize', () async {
      when(() => mockService.initialize()).thenAnswer((_) async {});
      await repository.initialize();
      verify(() => mockService.initialize()).called(1);
    });
  });

  group('speakWarning', () {
    test('delegates to service.speakWarning', () async {
      when(() => mockService.speakWarning('warning'))
          .thenAnswer((_) async => true);
      final result = await repository.speakWarning('warning');
      expect(result, isTrue);
      verify(() => mockService.speakWarning('warning')).called(1);
    });
  });

  group('speakImmediate', () {
    test('delegates to service.speakImmediate', () async {
      when(() => mockService.speakImmediate('urgent'))
          .thenAnswer((_) async => true);
      final result = await repository.speakImmediate('urgent');
      expect(result, isTrue);
      verify(() => mockService.speakImmediate('urgent')).called(1);
    });
  });

  group('stop', () {
    test('delegates to service.stop', () async {
      when(() => mockService.stop()).thenAnswer((_) async {});
      await repository.stop();
      verify(() => mockService.stop()).called(1);
    });
  });

  group('pause', () {
    test('delegates to service.pause', () async {
      when(() => mockService.pause()).thenAnswer((_) async {});
      await repository.pause();
      verify(() => mockService.pause()).called(1);
    });
  });

  group('isSpeaking', () {
    test('delegates to service.isSpeaking', () {
      when(() => mockService.isSpeaking).thenReturn(true);
      expect(repository.isSpeaking, isTrue);
      verify(() => mockService.isSpeaking).called(1);
    });

    test('returns false when service is not speaking', () {
      when(() => mockService.isSpeaking).thenReturn(false);
      expect(repository.isSpeaking, isFalse);
    });
  });

  group('configure', () {
    test('delegates to service.initialize with params', () async {
      when(() => mockService.initialize(
            language: any(named: 'language'),
            speechRate: any(named: 'speechRate'),
            pitch: any(named: 'pitch'),
            volume: any(named: 'volume'),
          )).thenAnswer((_) async {});

      await repository.configure(
        language: 'vi-VN',
        speechRate: 0.5,
        pitch: 1.0,
        volume: 1.0,
      );

      verify(() => mockService.initialize(
            language: 'vi-VN',
            speechRate: 0.5,
            pitch: 1.0,
            volume: 1.0,
          )).called(1);
    });
  });
}
