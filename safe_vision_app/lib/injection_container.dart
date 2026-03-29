import 'package:get_it/get_it.dart';
import 'core/services/camera_service.dart';
import 'features/detection/data/datasources/detection_local_datasource.dart';
import 'features/detection/data/datasources/detection_local_datasource_impl.dart';
import 'features/detection/data/repositories/detection_repository_impl.dart';
import 'features/detection/domain/repositories/detection_repository.dart';
import 'features/detection/domain/usecases/load_model_usecase.dart';
import 'features/detection/domain/usecases/detection_object_from_frame.dart';
import 'features/detection/presentation/bloc/detection_bloc.dart';
import 'features/tts/data/datasources/tts_service.dart';
import 'features/tts/data/repositories/tts_repository_impl.dart';
import 'features/tts/domain/repositories/tts_repository.dart';
import 'features/tts/domain/usecases/speak_warning_usecase.dart';
import 'features/tts/domain/usecases/stop_speaking_usecase.dart';
import 'features/tts/presentation/bloc/tts_bloc.dart';
import 'features/settings/data/datasources/local_storage_service.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/repositories/settings_repository.dart';
import 'features/settings/presentation/bloc/settings_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // ── TTS ─────────────────────────────────────────────────
  final ttsService = TtsService();
  await ttsService.initialize();
  sl.registerSingleton<TtsService>(ttsService);
  sl.registerSingleton<TtsRepository>(TtsRepositoryImpl(sl<TtsService>()));
  sl.registerSingleton(SpeakWarningUsecase(sl<TtsRepository>()));
  sl.registerSingleton(StopSpeakingUsecase(sl<TtsRepository>()));
  sl.registerSingleton(TtsBloc(
    speakWarning: sl(),
    stopSpeaking: sl(),
  ));

  // ── Detection ────────────────────────────────────────────
  sl.registerSingleton<DetectionLocalDatasource>(
    DetectionLocalDatasourceImpl(),
  );
  sl.registerSingleton<DetectionRepository>(
    DetectionRepositoryImpl(sl()),
  );
  sl.registerSingleton(LoadModelUsecase(sl<DetectionRepository>()));
  sl.registerSingleton(DetectionObjectFromFrame(sl<DetectionRepository>()));
  sl.registerFactory(() => DetectionBloc(
        loadModel: sl(),
        detectFromFrame: sl(),
        ttsBloc: sl<TtsBloc>(),
      ));

  // ── Camera ───────────────────────────────────────────────
  sl.registerSingleton(CameraService());

  // ── Settings ─────────────────────────────────────────────
  sl.registerSingleton(LocalStorageService());
  sl.registerSingleton<SettingsRepository>(
    SettingsRepositoryImpl(sl()),
  );
  sl.registerFactory(() => SettingsBloc(
        sl<SettingsRepository>(),
        sl<TtsService>(),
      ));
}
