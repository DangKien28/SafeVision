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

  group('TtsBloc — voice-disabled gate covers all TtsSpeak paths', () {
    setUp(() {
      when(() => mockSettings.getVoiceEnabled()).thenAnswer((_) async => false);
      when(() => mockRepo.stop()).thenAnswer((_) async {});
    });

    blocTest<TtsBloc, TtsState>(
      'immediate=false speak is silenced when voice is disabled',
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('warning text', immediate: false)),
      expect: () => [const TtsStopped()],
      verify: (_) {
        verifyNever(() => mockRepo.speakWarning(any()));
        verifyNever(() => mockRepo.speakImmediate(any()));
      },
    );

    blocTest<TtsBloc, TtsState>(
      'immediate=true speak is also silenced when voice is disabled',
      build: buildBloc,
      act: (bloc) => bloc.add(const TtsSpeak('urgent', immediate: true)),
      expect: () => [const TtsStopped()],
      verify: (_) {
        verifyNever(() => mockRepo.speakWarning(any()));
        verifyNever(() => mockRepo.speakImmediate(any()));
        verify(() => mockRepo.stop()).called(1);
      },
    );

    blocTest<TtsBloc, TtsState>(
      'multiple speaks while disabled each call stop() and emit TtsStopped once',
      build: buildBloc,
      seed: () => const TtsInitial(),
      act: (bloc) async {
        bloc.add(const TtsSpeak('first'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // State is now TtsStopped; second speak must NOT re-emit TtsStopped.
        bloc.add(const TtsSpeak('second'));
      },
      // Only the first TtsSpeak emits TtsStopped; subsequent ones are
      // suppressed by the `if (state is! TtsStopped)` guard.
      expect: () => [const TtsStopped()],
    );
  });

  group('TtsBloc — playback update stream', () {
    blocTest<TtsBloc, TtsState>(
      // Verifies that a `started` playback update does NOT re-dispatch TtsSpeak
      // (which would cause an infinite loop) and does NOT call speakWarning again.
      //
      // Note on the state sequence: BLoC suppresses emitting a state that is
      // identical to the current state.  After the TtsSpeak handler emits
      // TtsSpeaking('xin chào'), the _TtsPlaybackStarted handler tries to emit
      // the same TtsSpeaking('xin chào') — BLoC drops it because Equatable
      // considers the two states equal (props = [text]).
      // The important assertion is therefore in `verify`, not `expect`:
      // speakWarning must be called exactly once — not again when `started` fires.
      'started playback update emits TtsSpeaking without calling speakWarning again',
      setUp: () {
        when(() => mockSettings.getVoiceEnabled())
            .thenAnswer((_) async => true);
        when(() => mockRepo.speakWarning(any())).thenAnswer((_) async => true);
        when(() => mockRepo.stop()).thenAnswer((_) async {});
      },
      build: () => buildBloc(withPlaybackUpdates: true),
      act: (bloc) async {
        // Initial speak from the application.
        bloc.add(const TtsSpeak('xin chào'));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Engine confirms it started — should only mirror state, not re-speak.
        playbackController.add(
          const TtsPlaybackUpdate(
            status: TtsPlaybackStatus.started,
            text: 'xin chào',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Engine finished.
        playbackController.add(
          const TtsPlaybackUpdate(status: TtsPlaybackStatus.stopped),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
      // BLoC deduplicates equal states: after TtsSpeak emits TtsSpeaking('xin chào'),
      // the _TtsPlaybackStarted handler's identical emit is suppressed.
      // Actual emitted sequence is therefore just two states, not three.
      expect: () => [
        const TtsSpeaking('xin chào'), // from TtsSpeak handler
        const TtsStopped(), // from TtsStop handler
        // NOTE: _TtsPlaybackStarted also calls emit(TtsSpeaking('xin chào'))
        // but BLoC drops it because the state is already TtsSpeaking('xin chào').
      ],
      verify: (_) {
        // KEY assertion for Bug 9: speakWarning is called EXACTLY ONCE.
        // If the old code (TtsSpeak dispatched on 'started') were still present,
        // speakWarning would be called a second time here, triggering the loop.
        verify(() => mockRepo.speakWarning('xin chào')).called(1);
      },
    );
  });
}
