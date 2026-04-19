import '../../domain/repositories/voice_command_repository.dart';
import '../datasources/voice_command_datasource.dart';

class VoiceCommandRepositoryImpl implements VoiceCommandRepository {
  final VoiceCommandDatasource _datasource;

  VoiceCommandRepositoryImpl(this._datasource);

  @override
  Future<String?> listenObjectName({
    Duration listenFor = const Duration(seconds: 4),
    Duration pauseFor = const Duration(seconds: 2),
    String localeId = 'vi_VN',
  }) {
    return _datasource.listenOnce(
      listenFor: listenFor,
      pauseFor: pauseFor,
      localeId: localeId,
    );
  }
}
