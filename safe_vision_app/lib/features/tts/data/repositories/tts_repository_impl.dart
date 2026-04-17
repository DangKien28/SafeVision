import '../../../tts/domain/repositories/tts_repository.dart';
import '../datasources/tts_service.dart';

class TtsRepositoryImpl implements TtsRepository {
  TtsRepositoryImpl(this._service);

  final TtsService _service;

  @override
  Future<void> initialize() => _service.initialize();

  @override
  Future<bool> speakWarning(String text) => _service.speakWarning(text);

  @override
  Future<bool> speakImmediate(String text) => _service.speakImmediate(text);

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
