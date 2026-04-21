import '../../domain/repositories/tts_repository.dart';
import '../datasources/tts_service.dart';

class TtsRepositoryImpl implements TtsRepository {
  final TtsService _service;
  TtsRepositoryImpl(this._service);

  @override
  Future<void> initialize() => _service.initialize();
  @override
  Future<bool> speakWarning(String t) => _service.speakWarning(t);
  @override
  Future<bool> speakImmediate(String t) => _service.speakImmediate(t);
  @override
  Future<void> stop() => _service.stop();
  @override
  Future<void> pause() => _service.pause();
  @override
  bool get isSpeaking => _service.isSpeaking;

  @override
  Future<void> configure({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  }) =>
      _service.initialize(
        language: language,
        speechRate: speechRate,
        pitch: pitch,
        volume: volume,
      );
}
