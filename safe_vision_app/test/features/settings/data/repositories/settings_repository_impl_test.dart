import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safe_vision_app/features/settings/data/datasources/local_storage_service.dart';
import 'package:safe_vision_app/features/settings/data/repositories/settings_repository_impl.dart';

class MockLocalStorageService extends Mock implements LocalStorageService {}

void main() {
  late MockLocalStorageService mockStorage;
  late SettingsRepositoryImpl repository;

  setUp(() {
    mockStorage = MockLocalStorageService();
    repository = SettingsRepositoryImpl(mockStorage);
  });

  group('getSpeechRate', () {
    test('delegates to storage', () async {
      when(() => mockStorage.getSpeechRate()).thenAnswer((_) async => 0.5);
      final result = await repository.getSpeechRate();
      expect(result, 0.5);
      verify(() => mockStorage.getSpeechRate()).called(1);
    });
  });

  group('setSpeechRate', () {
    test('delegates to storage', () async {
      when(() => mockStorage.setSpeechRate(0.7)).thenAnswer((_) async {});
      await repository.setSpeechRate(0.7);
      verify(() => mockStorage.setSpeechRate(0.7)).called(1);
    });
  });

  group('getConfidenceThreshold', () {
    test('delegates to storage', () async {
      when(() => mockStorage.getConfidenceThreshold())
          .thenAnswer((_) async => 0.3);
      final result = await repository.getConfidenceThreshold();
      expect(result, 0.3);
      verify(() => mockStorage.getConfidenceThreshold()).called(1);
    });
  });

  group('setConfidenceThreshold', () {
    test('delegates to storage', () async {
      when(() => mockStorage.setConfidenceThreshold(0.5))
          .thenAnswer((_) async {});
      await repository.setConfidenceThreshold(0.5);
      verify(() => mockStorage.setConfidenceThreshold(0.5)).called(1);
    });
  });

  group('getVoiceEnabled', () {
    test('delegates to storage', () async {
      when(() => mockStorage.getVoiceEnabled()).thenAnswer((_) async => true);
      final result = await repository.getVoiceEnabled();
      expect(result, isTrue);
    });
  });

  group('setVoiceEnabled', () {
    test('delegates to storage', () async {
      when(() => mockStorage.setVoiceEnabled(false)).thenAnswer((_) async {});
      await repository.setVoiceEnabled(false);
      verify(() => mockStorage.setVoiceEnabled(false)).called(1);
    });
  });

  group('getShowConfidencePanel', () {
    test('delegates to storage', () async {
      when(() => mockStorage.getShowConfidencePanel())
          .thenAnswer((_) async => true);
      final result = await repository.getShowConfidencePanel();
      expect(result, isTrue);
    });
  });

  group('setShowConfidencePanel', () {
    test('delegates to storage', () async {
      when(() => mockStorage.setShowConfidencePanel(false))
          .thenAnswer((_) async {});
      await repository.setShowConfidencePanel(false);
      verify(() => mockStorage.setShowConfidencePanel(false)).called(1);
    });
  });

  group('getTtsLanguage', () {
    test('delegates to storage', () async {
      when(() => mockStorage.getTtsLanguage()).thenAnswer((_) async => 'vi-VN');
      final result = await repository.getTtsLanguage();
      expect(result, 'vi-VN');
    });
  });

  group('setTtsLanguage', () {
    test('delegates to storage', () async {
      when(() => mockStorage.setTtsLanguage('vi-VN')).thenAnswer((_) async {});
      await repository.setTtsLanguage('vi-VN');
      verify(() => mockStorage.setTtsLanguage('vi-VN')).called(1);
    });
  });
}
