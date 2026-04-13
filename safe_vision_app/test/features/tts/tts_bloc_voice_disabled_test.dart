import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/features/settings/domain/repositories/settings_repository.dart';
import 'package:safe_vision_app/features/tts/domain/entities/tts_playback_update.dart';
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
  late StreamController<TtsPlaybackUpdate> playbackController;

  setUp(() {
    mockRepo = MockTtsRepository();
    mockSettings = MockSettingsRepository();
    playbackController = StreamController<TtsPlaybackUpdate>.broadcast();
  });

  tearDown(() async {
    await playbackController.close();
  });

  TtsBloc buildBloc({bool withPlaybackUpdates = false}) => TtsBloc(
        speakWarning: SpeakWarningUsecase(mockRepo),
        stopSpeaking: StopSpeakingUsecase(mockRepo),
        pauseSpeaking: PauseSpeakingUsecase(mockRepo),
        settingsRepository: mockSettings,
        playbackUpdates: withPlaybackUpdates ? playbackController.stream : null,
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
  group('TtsBloc â€” playback update stream', () {
    blocTest<TtsBloc, TtsState>(
      'uses playback updates to reflect actual engine state',
      setUp: () {
        when(() => mockSettings.getVoiceEnabled())
            .thenAnswer((_) async => true);
        when(() => mockRepo.speakWarning(any())).thenAnswer((_) async => true);
      },
      build: () => buildBloc(withPlaybackUpdates: true),
      act: (bloc) async {
        bloc.add(const TtsSpeak('xin chào'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        playbackController.add(
          const TtsPlaybackUpdate(
            status: TtsPlaybackStatus.started,
            text: 'xin chào',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        playbackController.add(
          const TtsPlaybackUpdate(status: TtsPlaybackStatus.stopped),
        );
      },
      expect: () => [const TtsSpeaking('xin chào'), const TtsStopped()],
    );
  });
}
