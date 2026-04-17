import '../repositories/tts_repository.dart';

class ConfigureTtsUsecase {
  ConfigureTtsUsecase(this._repository);
  final TtsRepository _repository;

  Future<void> call({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  }) =>
      _repository.configure(
        language: language,
        speechRate: speechRate,
        pitch: pitch,
        volume: volume,
      );
}
