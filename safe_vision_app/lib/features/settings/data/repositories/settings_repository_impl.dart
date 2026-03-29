import '../../domain/repositories/settings_repository.dart';
import '../datasources/local_storage_service.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final LocalStorageService _storage;
  SettingsRepositoryImpl(this._storage);

  @override Future<double> getSpeechRate()           => _storage.getSpeechRate();
  @override Future<void>   setSpeechRate(double v)   => _storage.setSpeechRate(v);
  @override Future<double> getConfidenceThreshold()  => _storage.getConfidenceThreshold();
  @override Future<void>   setConfidenceThreshold(double v) => _storage.setConfidenceThreshold(v);
  @override Future<bool>   getVoiceEnabled()         => _storage.getVoiceEnabled();
  @override Future<void>   setVoiceEnabled(bool v)   => _storage.setVoiceEnabled(v);
  @override Future<bool>   getShowConfidencePanel()  => _storage.getShowConfidencePanel();
  @override Future<void>   setShowConfidencePanel(bool v) => _storage.setShowConfidencePanel(v);
  @override Future<String> getTtsLanguage()          => _storage.getTtsLanguage();
  @override Future<void>   setTtsLanguage(String v)  => _storage.setTtsLanguage(v);
}