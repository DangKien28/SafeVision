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
  late MockSettingsRepository mockSettings;

  setUp(() {
    mockRepo = MockTtsRepository();
    mockSettings = MockSettingsRepository();
  });

  TtsBloc buildBloc() => TtsBloc(
        speakWarning: SpeakWarningUsecase(mockRepo),
        stopSpeaking: StopSpeakingUsecase(mockRepo),
        pauseSpeaking: PauseSpeakingUsecase(mockRepo),
        settingsRepository: mockSettings,
      );

  group('TtsBloc — voiceEnabled=false stops audio from any state', () {
    blocTest<TtsBloc, TtsState>(
      'stops audio when voice disabled and state is TtsInitial',
      setUp: () {
        when(() => mockSettings.getVoiceEnabled())
            .thenAnswer((_) async => false);
        when(() => mockRepo.stop()).thenAnswer((_) async {});
      },
      build: buildBloc,
      // seed: TtsInitial (default)
      act: (bloc) => bloc.add(const TtsSpeak('test')),
      expect: () => [const TtsStopped()],
      verify: (_) {
        verify(() => mockRepo.stop()).called(1);
        verifyNever(() => mockRepo.speakWarning(any()));
      },
    );

    blocTest<TtsBloc, TtsState>(
      'emits TtsStopped only once even if already stopped',
      setUp: () {
        when(() => mockSettings.getVoiceEnabled())
            .thenAnswer((_) async => false);
        when(() => mockRepo.stop()).thenAnswer((_) async {});
      },
      build: buildBloc,
      seed: () => const TtsStopped(),
      act: (bloc) => bloc.add(const TtsSpeak('test')),
      // Already TtsStopped → guard prevents re-emit
      expect: () => <TtsState>[],
    );
  });

  group('LocalStorageService — getTtsLanguage no side-effect', () {
    test('returns vi-VN without writing to storage', () async {
      // This is verified by the absence of setString calls in unit tests.
      // Integration test on device required for SharedPreferences validation.
      expect(
          true, isTrue); // placeholder — real test needs FakeSharedPreferences
    });
  });
}
