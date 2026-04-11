import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_event.dart';
import 'package:safe_vision_app/features/tts/presentation/bloc/tts_state.dart';

void main() {
  group('TtsState', () {
    test('TtsInitial equality', () {
      const s1 = TtsInitial();
      const s2 = TtsInitial();
      expect(s1, equals(s2));
      expect(s1.props, isEmpty);
    });

    test('TtsSpeaking equality', () {
      const s1 = TtsSpeaking('hello');
      const s2 = TtsSpeaking('hello');
      const s3 = TtsSpeaking('world');
      expect(s1, equals(s2));
      expect(s1, isNot(equals(s3)));
      expect(s1.text, 'hello');
      expect(s1.props, ['hello']);
    });

    test('TtsStopped equality', () {
      const s1 = TtsStopped();
      const s2 = TtsStopped();
      expect(s1, equals(s2));
    });

    test('TtsPaused equality', () {
      const s1 = TtsPaused();
      const s2 = TtsPaused();
      expect(s1, equals(s2));
    });

    test('TtsError equality', () {
      const s1 = TtsError('err');
      const s2 = TtsError('err');
      const s3 = TtsError('other');
      expect(s1, equals(s2));
      expect(s1, isNot(equals(s3)));
      expect(s1.message, 'err');
      expect(s1.props, ['err']);
    });
  });

  group('TtsEvent', () {
    test('TtsSpeak equality', () {
      const e1 = TtsSpeak('text');
      const e2 = TtsSpeak('text');
      const e3 = TtsSpeak('other');
      expect(e1, equals(e2));
      expect(e1, isNot(equals(e3)));
    });

    test('TtsSpeak with options', () {
      const e = TtsSpeak('text', immediate: true, withVibration: true);
      expect(e.text, 'text');
      expect(e.immediate, isTrue);
      expect(e.withVibration, isTrue);
      expect(e.props, ['text', true, true]);
    });

    test('TtsSpeak default options', () {
      const e = TtsSpeak('text');
      expect(e.immediate, isFalse);
      expect(e.withVibration, isFalse);
    });

    test('TtsStop equality', () {
      const e1 = TtsStop();
      const e2 = TtsStop();
      expect(e1, equals(e2));
    });

    test('TtsPause equality', () {
      const e1 = TtsPause();
      const e2 = TtsPause();
      expect(e1, equals(e2));
    });
  });
}
