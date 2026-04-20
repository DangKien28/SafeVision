import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/features/tts/data/datasources/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  final calls = <MethodCall>[];
  var speakResult = 1;

  setUp(() async {
    calls.clear();
    speakResult = 1;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'speak':
          return speakResult;
        case 'stop':
        case 'pause':
        case 'setLanguage':
        case 'setSpeechRate':
        case 'setPitch':
        case 'setVolume':
        case 'setStartHandler':
        case 'setCompletionHandler':
        case 'setErrorHandler':
          return 1;
      }
      return null;
    });
  });

  tearDown(() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('TtsService', () {
    test('initialize configures language, speech rate, pitch and volume', () async {
      final service = TtsService();
      await service.initialize(
        language: 'vi-VN',
        speechRate: 0.6,
        pitch: 1.1,
        volume: 0.9,
      );

      final methods = calls.map((c) => c.method).toList();
      expect(methods, containsAll(<String>[
        'setLanguage',
        'setSpeechRate',
        'setPitch',
        'setVolume',
        'setStartHandler',
        'setCompletionHandler',
        'setErrorHandler',
      ]));
    });

    test('speakWarning auto-initializes and calls speak once', () async {
      final service = TtsService();
      final accepted = await service.speakWarning('Cảnh báo phía trước');

      expect(accepted, isTrue);
      final methods = calls.map((c) => c.method).toList();
      expect(methods.where((m) => m == 'speak').length, 1);
      expect(methods, contains('setLanguage'));
    });

    test('speakImmediate stops current speech before speaking', () async {
      final service = TtsService();
      final accepted = await service.speakImmediate('Nguy hiểm!');

      expect(accepted, isTrue);
      final methods = calls.map((c) => c.method).toList();
      final stopIndex = methods.indexOf('stop');
      final speakIndex = methods.indexOf('speak');
      expect(stopIndex, greaterThanOrEqualTo(0));
      expect(speakIndex, greaterThanOrEqualTo(0));
      expect(stopIndex, lessThan(speakIndex));
    });

    test('speakWarning returns false when platform returns non-success', () async {
      speakResult = 0;
      final service = TtsService();

      final accepted = await service.speakWarning('không đọc được');

      expect(accepted, isFalse);
    });

    test('stop and pause delegate to platform methods', () async {
      final service = TtsService();
      await service.stop();
      await service.pause();

      final methods = calls.map((c) => c.method).toList();
      expect(methods, contains('stop'));
      expect(methods, contains('pause'));
    });
  });
}
