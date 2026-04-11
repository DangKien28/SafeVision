import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/core/config/detection_config.dart';
import 'package:safe_vision_app/core/constants/app_constants.dart';
import 'package:safe_vision_app/features/settings/domain/repositories/settings_repository.dart';
import 'package:safe_vision_app/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:safe_vision_app/features/settings/presentation/bloc/settings_event.dart';
import 'package:safe_vision_app/features/settings/presentation/bloc/settings_state.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/configure_tts_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/usecases/stop_speaking_usecase.dart';
import 'package:safe_vision_app/features/tts/domain/repositories/tts_repository.dart';

class MockSettingsRepository extends Mock implements SettingsRepository {}

class MockTtsRepository extends Mock implements TtsRepository {}

void main() {
  late MockSettingsRepository mockRepo;
  late ConfigureTtsUsecase configureTts;
  late StopSpeakingUsecase stopSpeaking;
  late DetectionConfig detectionConfig;
  late MockTtsRepository mockTtsRepo;

  /// Records configure() calls so the test can verify the parameters.
  final List<Map<String, dynamic>> capturedConfigCalls = [];

  setUp(() {
    mockRepo = MockSettingsRepository();
    mockTtsRepo = MockTtsRepository();
    detectionConfig = DetectionConfig();
    capturedConfigCalls.clear();

    configureTts = ConfigureTtsUsecase(mockTtsRepo);
    stopSpeaking = StopSpeakingUsecase(mockTtsRepo);

    when(() => mockRepo.getSpeechRate())
        .thenAnswer((_) async => AppConstants.ttsSpeechRate);
    when(() => mockRepo.getConfidenceThreshold())
        .thenAnswer((_) async => AppConstants.confidenceThreshold);
    when(() => mockRepo.getVoiceEnabled()).thenAnswer((_) async => true);
    when(() => mockRepo.getShowConfidencePanel()).thenAnswer((_) async => true);
    when(() => mockRepo.getTtsLanguage()).thenAnswer((_) async => 'vi-VN');
    when(() => mockRepo.setTtsLanguage(any())).thenAnswer((_) async {});
    when(() => mockRepo.setSpeechRate(any())).thenAnswer((_) async {});
    when(() => mockRepo.setVoiceEnabled(any())).thenAnswer((_) async {});
    when(() => mockRepo.setConfidenceThreshold(any())).thenAnswer((_) async {});
    when(() => mockRepo.setShowConfidencePanel(any())).thenAnswer((_) async {});

    when(() => mockTtsRepo.configure(
          language: any(named: 'language'),
          speechRate: any(named: 'speechRate'),
          pitch: any(named: 'pitch'),
          volume: any(named: 'volume'),
        )).thenAnswer((invocation) async {
      capturedConfigCalls.add({
        'language': invocation.namedArguments[const Symbol('language')],
        'speechRate': invocation.namedArguments[const Symbol('speechRate')],
      });
    });

    when(() => mockTtsRepo.stop()).thenAnswer((_) async {});
  });

  SettingsBloc buildBloc() =>
      SettingsBloc(mockRepo, configureTts, stopSpeaking, detectionConfig);

  // Invariant: language updates preserve the current speechRate.

  group('SettingsTtsLanguageChanged — luôn giữ tiếng Việt', () {
    blocTest<SettingsBloc, SettingsState>(
      'yêu cầu đổi ngôn ngữ vẫn giữ speechRate hiện tại của TTS',
      build: () {
        when(() => mockRepo.getSpeechRate()).thenAnswer((_) async => 0.75);
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsTtsLanguageChanged());
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (_) {
        final langChangeCalls =
            capturedConfigCalls.where((c) => c['language'] == 'vi-VN').toList();

        expect(langChangeCalls, isNotEmpty,
            reason: 'TTS phải được cấu hình lại khi xử lý đổi ngôn ngữ');

        expect(langChangeCalls.last['speechRate'], equals(0.75),
            reason: 'speechRate 0.75 phải được truyền lại cùng ngôn ngữ. '
                'Nếu không, engine có thể quay về tốc độ mặc định.');
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'state sau khi đổi ngôn ngữ vẫn giữ speechRate và khóa về tiếng Việt',
      build: () {
        when(() => mockRepo.getSpeechRate()).thenAnswer((_) async => 0.6);
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsTtsLanguageChanged());
      },
      expect: () => [
        isA<SettingsState>().having((s) => s.isLoading, 'isLoading', isTrue),
        isA<SettingsState>()
            .having((s) => s.isLoading, 'isLoading', isFalse)
            .having((s) => s.speechRate, 'speechRate', closeTo(0.6, 0.001)),
        isA<SettingsState>()
            .having((s) => s.ttsLanguage, 'ttsLanguage', 'vi-VN')
            .having((s) => s.speechRate, 'speechRate', closeTo(0.6, 0.001)),
      ],
    );

    blocTest<SettingsBloc, SettingsState>(
      'đổi tốc độ rồi đổi ngôn ngữ vẫn dùng tốc độ mới nhất',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsSpeechRateChanged(0.8));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsTtsLanguageChanged());
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (_) {
        final langCalls =
            capturedConfigCalls.where((c) => c['language'] == 'vi-VN').toList();

        expect(langCalls, isNotEmpty);
        expect(langCalls.last['speechRate'], closeTo(0.8, 0.001),
            reason:
                'Sau khi đặt tốc độ 0.8, lần cấu hình kế tiếp vẫn phải dùng 0.8.');
      },
    );
  });

  // speechRate change

  group('SettingsSpeechRateChanged', () {
    blocTest<SettingsBloc, SettingsState>(
      'cấu hình TTS luôn truyền cả tốc độ đọc và ngôn ngữ',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsSpeechRateChanged(0.75));
      },
      verify: (_) {
        final rateCalls =
            capturedConfigCalls.where((c) => c['speechRate'] == 0.75).toList();
        expect(rateCalls, isNotEmpty);
        expect(rateCalls.last['language'], equals('vi-VN'),
            reason: 'Ngôn ngữ TTS phải luôn được cố định là tiếng Việt');
      },
    );
  });

  // Confidence threshold -> DetectionConfig

  group('SettingsConfidenceChanged', () {
    blocTest<SettingsBloc, SettingsState>(
      'thay đổi confidence được áp dụng ngay vào DetectionConfig',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsConfidenceChanged(0.65));
      },
      verify: (_) {
        expect(
          detectionConfig.confidenceThreshold,
          closeTo(0.65, 0.001),
          reason: 'DetectionConfig phải được cập nhật ngay để frame kế tiếp '
              'dùng ngưỡng mới mà không cần khởi động lại model',
        );
      },
    );
  });

  // Voice toggle

  group('SettingsVoiceToggled', () {
    blocTest<SettingsBloc, SettingsState>(
      'tắt giọng đọc sẽ gọi stopSpeaking',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsVoiceToggled(false));
      },
      expect: () => [
        isA<SettingsState>().having((s) => s.isLoading, '', isTrue),
        isA<SettingsState>().having((s) => s.voiceEnabled, '', isTrue),
        isA<SettingsState>().having((s) => s.voiceEnabled, '', isFalse),
      ],
      verify: (_) => verify(() => mockTtsRepo.stop()).called(1),
    );

    blocTest<SettingsBloc, SettingsState>(
      'bật giọng đọc không gọi stopSpeaking',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const SettingsLoaded());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const SettingsVoiceToggled(true));
      },
      verify: (_) => verifyNever(() => mockTtsRepo.stop()),
    );
  });
}
