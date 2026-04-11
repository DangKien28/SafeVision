import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safe_vision_app/features/tts/domain/repositories/tts_repository.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/configure_tts_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/pause_speaking_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/speak_warning_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/stop_speaking_usecase.dart';

class MockTtsRepository extends Mock implements TtsRepository {}

void main() {
  late MockTtsRepository mockRepo;

  setUp(() {
    mockRepo = MockTtsRepository();
  });

  group('SpeakWarningUsecase', () {
    late SpeakWarningUsecase usecase;

    setUp(() {
      usecase = SpeakWarningUsecase(mockRepo);
    });

    test('call delegates to repository.speakWarning', () async {
      when(() => mockRepo.speakWarning('hello')).thenAnswer((_) async => true);
      final result = await usecase('hello');
      expect(result, isTrue);
      verify(() => mockRepo.speakWarning('hello')).called(1);
    });

    test('call returns false when repo returns false', () async {
      when(() => mockRepo.speakWarning('test')).thenAnswer((_) async => false);
      final result = await usecase('test');
      expect(result, isFalse);
    });

    test('immediate delegates to repository.speakImmediate', () async {
      when(() => mockRepo.speakImmediate('urgent'))
          .thenAnswer((_) async => true);
      final result = await usecase.immediate('urgent');
      expect(result, isTrue);
      verify(() => mockRepo.speakImmediate('urgent')).called(1);
    });
  });

  group('StopSpeakingUsecase', () {
    late StopSpeakingUsecase usecase;

    setUp(() {
      usecase = StopSpeakingUsecase(mockRepo);
    });

    test('call delegates to repository.stop', () async {
      when(() => mockRepo.stop()).thenAnswer((_) async {});
      await usecase();
      verify(() => mockRepo.stop()).called(1);
    });
  });

  group('PauseSpeakingUsecase', () {
    late PauseSpeakingUsecase usecase;

    setUp(() {
      usecase = PauseSpeakingUsecase(mockRepo);
    });

    test('call delegates to repository.pause', () async {
      when(() => mockRepo.pause()).thenAnswer((_) async {});
      await usecase();
      verify(() => mockRepo.pause()).called(1);
    });
  });

  group('ConfigureTtsUsecase', () {
    late ConfigureTtsUsecase usecase;

    setUp(() {
      usecase = ConfigureTtsUsecase(mockRepo);
    });

    test('call delegates to repository.configure with all params', () async {
      when(() => mockRepo.configure(
            language: any(named: 'language'),
            speechRate: any(named: 'speechRate'),
            pitch: any(named: 'pitch'),
            volume: any(named: 'volume'),
          )).thenAnswer((_) async {});

      await usecase(
        language: 'vi-VN',
        speechRate: 0.5,
        pitch: 1.0,
        volume: 1.0,
      );

      verify(() => mockRepo.configure(
            language: 'vi-VN',
            speechRate: 0.5,
            pitch: 1.0,
            volume: 1.0,
          )).called(1);
    });

    test('call delegates with null optional params', () async {
      when(() => mockRepo.configure(
            language: any(named: 'language'),
            speechRate: any(named: 'speechRate'),
            pitch: any(named: 'pitch'),
            volume: any(named: 'volume'),
          )).thenAnswer((_) async {});

      await usecase(speechRate: 0.7);

      verify(() => mockRepo.configure(
            language: null,
            speechRate: 0.7,
            pitch: null,
            volume: null,
          )).called(1);
    });
  });
}
