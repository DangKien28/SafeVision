import 'package:get_it/get_it.dart';

import 'core/config/detection_config.dart';
import 'core/constants/app_constants.dart';
import 'core/services/camera_service.dart';
import 'features/detection/data/datasources/detection_local_datasource.dart';
import 'features/detection/data/datasources/detection_local_datasource_impl.dart';
import 'features/detection/data/datasources/hybrid_detection_local_datasource_impl.dart';
import 'features/detection/data/datasources/mlkit_detection_local_datasource_impl.dart';
import 'features/detection/data/repositories/detection_repository_impl.dart';
import 'features/detection/domain/repositories/detection_repository.dart';
import 'features/detection/domain/usecases/close_model_usecase.dart';
import 'features/detection/domain/usecases/detection_object_from_frame.dart';
import 'features/detection/domain/usecases/load_model_usecase.dart';
import 'features/settings/data/datasources/local_storage_service.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/repositories/settings_repository.dart';
import 'features/settings/presentation/bloc/settings_bloc.dart';
import 'features/tts/data/datasources/tts_service.dart';
import 'features/tts/data/repositories/tts_repository_impl.dart';
import 'features/tts/domain/repositories/tts_repository.dart';
import 'features/tts/domain/usecases/configure_tts_usecase.dart';
import 'features/tts/domain/usecases/pause_speaking_usecase.dart';
import 'features/tts/domain/usecases/speak_warning_usecase.dart';
import 'features/tts/domain/usecases/stop_speaking_usecase.dart';
import 'features/tts/presentation/bloc/tts_bloc.dart';

final sl = GetIt.instance;

/// Registers all dependencies.
///
/// Call once from [main] before [runApp].  Does NOT perform any async work —
/// heavy initialization is deferred to the first time each singleton is used.
///
/// ## Bug fixed: startup latency from eager TTS initialization
///
/// The previous implementation called `TtsService.initialize()` eagerly inside
/// `registerSingleton`, which blocked the DI container's initialization
/// thread on every cold launch — even before the first frame was drawn.
///
/// Fix: [TtsService] is now registered with [registerLazySingleton].  The
/// singleton is created on first access, and `initialize()` is called lazily
/// inside [TtsBloc] (or [SettingsBloc]) the first time TTS is needed.  This
/// removes the startup penalty entirely.
///
/// ### Singleton vs LazySingleton policy (from architecture docs)
///
/// | Strategy                | When to use |
/// |-------------------------|-------------|
/// | `registerSingleton`     | Service that MUST be fully warm before the app runs (none currently) |
/// | `registerLazySingleton` | Everything else — created on first access |
Future<void> initDependencies() async {
  // ── Camera ──────────────────────────────────────────────────────────────────
  sl.registerLazySingleton<CameraService>(CameraService.new);

  // ── Detection config (shared mutable config — singleton) ────────────────────
  sl.registerLazySingleton<DetectionConfig>(DetectionConfig.new);

  // ── Detection datasource & repository ──────────────────────────────────────
  sl.registerLazySingleton<DetectionLocalDatasource>(
    () => HybridDetectionLocalDatasourceImpl(
      primaryDatasource: DetectionLocalDatasourceImpl(sl<DetectionConfig>()),
      fallbackDatasource: MlKitDetectionLocalDatasourceImpl(
        sl<DetectionConfig>(),
      ),
      enableFallback: AppConstants.enableMlKitFallback,
      fallbackIntervalFrames: AppConstants.mlKitFallbackIntervalFrames,
    ),
  );

  sl.registerLazySingleton<DetectionRepository>(
    () => DetectionRepositoryImpl(sl<DetectionLocalDatasource>()),
  );

  // ── Detection use cases ─────────────────────────────────────────────────────
  sl.registerLazySingleton(
    () => LoadModelUsecase(sl<DetectionRepository>()),
  );
  sl.registerLazySingleton(
    () => CloseModelUsecase(sl<DetectionRepository>()),
  );
  sl.registerLazySingleton(
    () => DetectionObjectFromFrame(sl<DetectionRepository>()),
  );

  // ── Settings datasource & repository ───────────────────────────────────────
  // LocalStorageService wraps SharedPreferences — lazy so plugin registration
  // happens after runApp.
  sl.registerLazySingleton<LocalStorageService>(LocalStorageService.new);

  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(sl<LocalStorageService>()),
  );

  // ── TTS datasource & repository ─────────────────────────────────────────────
  //
  // BUG FIX: was `registerSingleton(() { final s = TtsService(); s.initialize(); return s; })`
  // which called initialize() eagerly, adding 200-400 ms to cold launch time.
  //
  // Fix: register as lazy.  `initialize()` is called on first TtsBloc creation,
  // at which point the audio engine is guaranteed to be available (post-runApp).
  sl.registerLazySingleton<TtsService>(TtsService.new);

  sl.registerLazySingleton<TtsRepository>(
    () => TtsRepositoryImpl(sl<TtsService>()),
  );

  // ── TTS use cases ───────────────────────────────────────────────────────────
  sl.registerLazySingleton(
    () => SpeakWarningUsecase(sl<TtsRepository>()),
  );
  sl.registerLazySingleton(
    () => StopSpeakingUsecase(sl<TtsRepository>()),
  );
  sl.registerLazySingleton(
    () => PauseSpeakingUsecase(sl<TtsRepository>()),
  );
  sl.registerLazySingleton(
    () => ConfigureTtsUsecase(sl<TtsRepository>()),
  );

  // ── BLoCs (lazy — created when the page that needs them mounts) ─────────────
  //
  // BLoCs are NOT singletons: each page that mounts a BlocProvider gets a fresh
  // BLoC instance.  registerFactory ensures this.
  sl.registerFactory(
    () => TtsBloc(
      speakWarning: sl<SpeakWarningUsecase>(),
      stopSpeaking: sl<StopSpeakingUsecase>(),
      pauseSpeaking: sl<PauseSpeakingUsecase>(),
      settingsRepository: sl<SettingsRepository>(),
    ),
  );

  sl.registerFactory(
    () => SettingsBloc(
      sl<SettingsRepository>(),
      sl<ConfigureTtsUsecase>(),
      sl<StopSpeakingUsecase>(),
      sl<DetectionConfig>(),
    ),
  );
}
