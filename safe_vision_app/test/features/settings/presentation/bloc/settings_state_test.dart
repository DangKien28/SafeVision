import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/constants/app_constants.dart';
import 'package:safe_vision_app/features/settings/presentation/bloc/settings_event.dart';
import 'package:safe_vision_app/features/settings/presentation/bloc/settings_state.dart';

void main() {
  group('SettingsState', () {
    test('default constructor has expected defaults', () {
      const state = SettingsState();
      expect(state.speechRate, AppConstants.ttsSpeechRate);
      expect(state.confidenceThreshold, AppConstants.confidenceThreshold);
      expect(state.voiceEnabled, isTrue);
      expect(state.showConfidencePanel, isTrue);
      expect(state.ttsLanguage, '');
      expect(state.isLoading, isFalse);
    });

    test('copyWith updates individual fields', () {
      const state = SettingsState();
      final updated = state.copyWith(speechRate: 0.8);
      expect(updated.speechRate, 0.8);
      expect(updated.confidenceThreshold, state.confidenceThreshold);
      expect(updated.voiceEnabled, state.voiceEnabled);
    });

    test('copyWith with all fields', () {
      const state = SettingsState();
      final updated = state.copyWith(
        speechRate: 0.7,
        confidenceThreshold: 0.5,
        voiceEnabled: false,
        showConfidencePanel: false,
        ttsLanguage: 'en-US',
        isLoading: true,
      );
      expect(updated.speechRate, 0.7);
      expect(updated.confidenceThreshold, 0.5);
      expect(updated.voiceEnabled, isFalse);
      expect(updated.showConfidencePanel, isFalse);
      expect(updated.ttsLanguage, 'en-US');
      expect(updated.isLoading, isTrue);
    });

    test('Equatable equality', () {
      const s1 = SettingsState();
      const s2 = SettingsState();
      expect(s1, equals(s2));
    });

    test('Equatable inequality', () {
      const s1 = SettingsState();
      final s2 = s1.copyWith(voiceEnabled: false);
      expect(s1, isNot(equals(s2)));
    });

    test('props contains all fields', () {
      const state = SettingsState();
      expect(state.props.length, 6);
    });
  });

  group('SettingsEvent', () {
    test('SettingsLoaded equality', () {
      const e1 = SettingsLoaded();
      const e2 = SettingsLoaded();
      expect(e1, equals(e2));
    });

    test('SettingsSpeechRateChanged stores rate', () {
      const e = SettingsSpeechRateChanged(0.7);
      expect(e.rate, 0.7);
      expect(e.props, [0.7]);
    });

    test('SettingsConfidenceChanged stores threshold', () {
      const e = SettingsConfidenceChanged(0.4);
      expect(e.threshold, 0.4);
      expect(e.props, [0.4]);
    });

    test('SettingsVoiceToggled stores enabled', () {
      const e = SettingsVoiceToggled(false);
      expect(e.enabled, isFalse);
      expect(e.props, [false]);
    });

    test('SettingsConfidencePanelToggled stores show', () {
      const e = SettingsConfidencePanelToggled(true);
      expect(e.show, isTrue);
      expect(e.props, [true]);
    });

    test('SettingsTtsLanguageChanged equality', () {
      const e1 = SettingsTtsLanguageChanged();
      const e2 = SettingsTtsLanguageChanged();
      expect(e1, equals(e2));
      expect(e1.props, isEmpty);
    });
  });
}
