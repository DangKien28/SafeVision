import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/features/settings/domain/repositories/settings_repository.dart';
import 'package:safe_vision_app/features/tts/domain/repositories/tts_repository.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/pause_speaking_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/speak_warning_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/stop_speaking_usecase.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_bloc.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_event.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_state.dart';

class MockTtsRepository extends Mock implements TtsRepository {}

class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  late MockTtsRepository mockRepo;
  late MockSettingsRepository mockSettingsRepository;

  setUp(() {
    mockRepo = MockTtsRepository();
    mockSettingsRepository = MockSettingsRepository();
    when(() => mockSettingsRepository.getVoiceEnabled())
        .thenAnswer((_) async => true);
  });

  // ─── SpeakWarningUsecase ──────────────────────────────────────────────────

  group('SpeakWarningUsecase', () {
    late SpeakWarningUsecase usecase;

    setUp(() => usecase = SpeakWarningUsecase(mockRepo));

    test('call() chuyển tiếp sang repository.speakWarning()', () async {
      const text = 'Cảnh báo! Người đi bộ ở phía trước, gần.';
      // speakWarning returns Future<bool> — stub must match the declared type.
      when(() => mockRepo.speakWarning(text)).thenAnswer((_) async => true);

      await usecase(text);

      verify(() => mockRepo.speakWarning(text)).called(1);
    });

    test('immediate() chuyển tiếp sang repository.speakImmediate()', () async {
      const text = 'Cảnh báo! Người đi bộ ở phía trước, rất gần.';
      // speakImmediate returns Future<bool> — stub must match the declared type.
      when(() => mockRepo.speakImmediate(text)).thenAnswer((_) async => true);

      await usecase.immediate(text);

      verify(() => mockRepo.speakImmediate(text)).called(1);
    });

    test('call() does not call speakImmediate()', () async {
      when(() => mockRepo.speakWarning(any())).thenAnswer((_) async => true);

      await usecase('test');

      verifyNever(() => mockRepo.speakImmediate(any()));
    });

    test('immediate() does not call speakWarning()', () async {
      when(() => mockRepo.speakImmediate(any())).thenAnswer((_) async => true);

      await usecase.immediate('test');

      verifyNever(() => mockRepo.speakWarning(any()));
    });

    test('passes exact content to repository', () async {
      const exactText = 'Cảnh báo! Xe đạp ở bên trái, khoảng cách trung bình.';
      when(() => mockRepo.speakWarning(exactText))
          .thenAnswer((_) async => true);

      await usecase(exactText);

      verify(() => mockRepo.speakWarning(exactText)).called(1);
    });

    test('call() truyền tiếp exception từ repository', () async {
      when(() => mockRepo.speakWarning(any()))
          .thenThrow(Exception('TTS engine error'));

      expect(() => usecase('text'), throwsException);
    });

    test('immediate() truyền tiếp exception từ repository', () async {
      when(() => mockRepo.speakImmediate(any()))
          .thenThrow(Exception('TTS engine error'));

      expect(() => usecase.immediate('text'), throwsException);
    });

    test('empty string is still forwarded to repository', () async {
      when(() => mockRepo.speakWarning('')).thenAnswer((_) async => true);

      await usecase('');

      verify(() => mockRepo.speakWarning('')).called(1);
    });

    test('each call is forwarded independently', () async {
      when(() => mockRepo.speakWarning(any())).thenAnswer((_) async => true);

      await usecase('cảnh báo thứ nhất');
      await usecase('cảnh báo thứ hai');
      await usecase('cảnh báo thứ ba');

      verify(() => mockRepo.speakWarning(any())).called(3);
    });
  });

  // ─── StopSpeakingUsecase ──────────────────────────────────────────────────

  group('StopSpeakingUsecase', () {
    late StopSpeakingUsecase usecase;

    setUp(() => usecase = StopSpeakingUsecase(mockRepo));

    test('call() chuyển tiếp sang repository.stop()', () async {
      when(() => mockRepo.stop()).thenAnswer((_) async {});

      await usecase();

      verify(() => mockRepo.stop()).called(1);
    });

    test('does not call voice rendering functions', () async {
      when(() => mockRepo.stop()).thenAnswer((_) async {});

      await usecase();

      verifyNever(() => mockRepo.speakWarning(any()));
      verifyNever(() => mockRepo.speakImmediate(any()));
    });

    test('truyền tiếp exception từ repository', () async {
      when(() => mockRepo.stop()).thenThrow(Exception('stop failed'));

      expect(() => usecase(), throwsException);
    });

    test('multiple stop calls are all fully forwarded', () async {
      when(() => mockRepo.stop()).thenAnswer((_) async {});

      await usecase();
      await usecase();

      verify(() => mockRepo.stop()).called(2);
    });
  });

  // ─── PauseSpeakingUsecase ─────────────────────────────────────────────────

  group('PauseSpeakingUsecase', () {
    late PauseSpeakingUsecase usecase;

    setUp(() => usecase = PauseSpeakingUsecase(mockRepo));

    test('call() chuyển tiếp sang repository.pause()', () async {
      when(() => mockRepo.pause()).thenAnswer((_) async {});

      await usecase();

      verify(() => mockRepo.pause()).called(1);
    });

    test('truyền tiếp exception từ repository', () async {
      when(() => mockRepo.pause()).thenThrow(Exception('pause failed'));

      expect(() => usecase(), throwsException);
    });
  });

  // ─── TtsBloc ──────────────────────────────────────────────────────────────

  group('TtsBloc', () {
    late SpeakWarningUsecase speakWarningUsecase;
    late StopSpeakingUsecase stopSpeakingUsecase;
    late PauseSpeakingUsecase pauseSpeakingUsecase;

    setUp(() {
      speakWarningUsecase = SpeakWarningUsecase(mockRepo);
      stopSpeakingUsecase = StopSpeakingUsecase(mockRepo);
      pauseSpeakingUsecase = PauseSpeakingUsecase(mockRepo);
    });

    TtsBloc buildBloc() => TtsBloc(
          speakWarning: speakWarningUsecase,
          stopSpeaking: stopSpeakingUsecase,
          pauseSpeaking: pauseSpeakingUsecase,
          settingsRepository: mockSettingsRepository,
        );

    test('state ban đầu là TtsInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const TtsInitial());
      bloc.close();
    });

    blocTest<TtsBloc, TtsState>(
      'TtsSpeak hàng đợi → gọi speakWarning và phát ra TtsSpeaking',
      // speakWarning returns Future<bool>; returning true means TTS accepted the call.
      setUp: () => when(() => mockRepo.speakWarning(any()))
          .thenAnswer((_) async => true),
      build: buildBloc,
      act: (bloc) =>
          bloc.add(const TtsSpeak('Cảnh báo! Người đi bộ ở phía trước.')),
      expect: () => [const TtsSpeaking('Cảnh báo! Người đi bộ ở phía trước.')],
      verify: (_) => verify(() => mockRepo.speakWarning(
            'Cảnh báo! Người đi bộ ở phía trước.',
          )).called(1),
    );

    blocTest<TtsBloc, TtsState>(
      'TtsSpeak(immediate:true) → gọi speakImmediate và phát ra TtsSpeaking',
      // speakImmediate returns Future<bool>; returning true means TTS accepted.
      setUp: () => when(() => mockRepo.speakImmediate(any()))
          .thenAnswer((_) async => true),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('Cảnh báo! Vật thể rất gần.',
          immediate: true, withVibration: false)),
      expect: () => [const TtsSpeaking('Cảnh báo! Vật thể rất gần.')],
      verify: (_) {
        verify(() => mockRepo.speakImmediate('Cảnh báo! Vật thể rất gần.'))
            .called(1);
        verifyNever(() => mockRepo.speakWarning(any()));
      },
    );

    blocTest<TtsBloc, TtsState>(
      'TtsStop → gọi repository.stop() và phát ra TtsStopped',
      setUp: () => when(() => mockRepo.stop()).thenAnswer((_) async {}),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsStop()),
      expect: () => [const TtsStopped()],
      verify: (_) => verify(() => mockRepo.stop()).called(1),
    );

    blocTest<TtsBloc, TtsState>(
      'TtsPause → gọi repository.pause() và phát ra TtsPaused',
      setUp: () => when(() => mockRepo.pause()).thenAnswer((_) async {}),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsPause()),
      expect: () => [const TtsPaused()],
      verify: (_) {
        verify(() => mockRepo.pause()).called(1);
        verifyNever(() => mockRepo.stop());
        verifyNever(() => mockRepo.speakWarning(any()));
      },
    );

    blocTest<TtsBloc, TtsState>(
      'TtsSpeak phát ra TtsError khi speakWarning ném lỗi',
      setUp: () => when(() => mockRepo.speakWarning(any()))
          .thenThrow(Exception('engine crashed')),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('test')),
      expect: () => [isA<TtsError>()],
    );

    blocTest<TtsBloc, TtsState>(
      'không phát giọng nói khi tính năng voice bị tắt trong cài đặt',
      setUp: () {
        when(() => mockSettingsRepository.getVoiceEnabled())
            .thenAnswer((_) async => false);
        when(() => mockRepo.stop()).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('test')),
      expect: () => [const TtsStopped()],
      verify: (_) {
        verify(() => mockRepo.stop()).called(1);
        verifyNever(() => mockRepo.speakWarning(any()));
        verifyNever(() => mockRepo.speakImmediate(any()));
      },
    );

    blocTest<TtsBloc, TtsState>(
      'TtsError chứa thông điệp lỗi lấy từ exception',
      setUp: () => when(() => mockRepo.speakWarning(any()))
          .thenThrow(Exception('engine crashed')),
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('test')),
      expect: () => [
        predicate<TtsState>(
          (s) => s is TtsError && s.message.contains('engine crashed'),
          'TtsError có chứa engine crashed',
        ),
      ],
    );

    blocTest<TtsBloc, TtsState>(
      'chuỗi speak rồi stop phát ra [TtsSpeaking, TtsStopped]',
      setUp: () {
        when(() => mockRepo.speakWarning(any())).thenAnswer((_) async => true);
        when(() => mockRepo.stop()).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const TtsSpeak('xin chào'));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const TtsStop());
      },
      expect: () => [const TtsSpeaking('xin chào'), const TtsStopped()],
    );
  });

  // ─── TtsEvent equality ────────────────────────────────────────────────────

  group('So sánh TtsEvent', () {
    test('TtsSpeak with identical parameters are equal', () {
      const a = TtsSpeak('xin chào', immediate: true, withVibration: true);
      const b = TtsSpeak('xin chào', immediate: true, withVibration: true);
      expect(a, equals(b));
    });

    test('TtsSpeak with different contents are not equal', () {
      const a = TtsSpeak('xin chào');
      const b = TtsSpeak('tạm biệt');
      expect(a, isNot(equals(b)));
    });

    test('TtsSpeak with different immediate flags are not equal', () {
      const a = TtsSpeak('xin chào', immediate: true);
      const b = TtsSpeak('xin chào', immediate: false);
      expect(a, isNot(equals(b)));
    });

    test('TtsStop equals another TtsStop', () {
      expect(const TtsStop(), equals(const TtsStop()));
    });

    test('TtsPause equals another TtsPause', () {
      expect(const TtsPause(), equals(const TtsPause()));
    });
  });

  // ─── TtsState equality ────────────────────────────────────────────────────

  group('So sánh TtsState', () {
    test('TtsInitial bằng nhau',
        () => expect(const TtsInitial(), equals(const TtsInitial())));

    test('TtsSpeaking with identical content are equal', () {
      expect(const TtsSpeaking('text'), equals(const TtsSpeaking('text')));
    });

    test('TtsSpeaking with different contents are not equal', () {
      expect(const TtsSpeaking('xin chào'),
          isNot(equals(const TtsSpeaking('tạm biệt'))));
    });

    test('TtsStopped bằng nhau',
        () => expect(const TtsStopped(), equals(const TtsStopped())));

    test('TtsPaused bằng nhau',
        () => expect(const TtsPaused(), equals(const TtsPaused())));

    test('TtsError with identical message are equal', () {
      expect(const TtsError('oops'), equals(const TtsError('oops')));
    });

    test('TtsError with different messages are not equal', () {
      expect(const TtsError('err1'), isNot(equals(const TtsError('err2'))));
    });
  });
}
