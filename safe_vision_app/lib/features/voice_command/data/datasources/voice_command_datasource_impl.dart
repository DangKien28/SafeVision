import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'voice_command_datasource.dart';

class VoiceCommandDatasourceImpl implements VoiceCommandDatasource {
  final SpeechToText _stt;

  VoiceCommandDatasourceImpl([SpeechToText? stt]) : _stt = stt ?? SpeechToText();

  @override
  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 4),
    Duration pauseFor = const Duration(seconds: 2),
    String localeId = 'vi_VN',
  }) async {
    try {
      String bestText = '';
      final completer = Completer<String?>();

      final ready = await _stt.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') &&
              !completer.isCompleted) {
            completer.complete(bestText.isEmpty ? null : bestText);
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.complete(bestText.isEmpty ? null : bestText);
          }
        },
      );
      if (!ready) return null;

      await _stt.listen(
        localeId: localeId,
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenOptions: SpeechListenOptions(
          partialResults: true,
        ),
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            bestText = words;
          }
          if (result.finalResult && !completer.isCompleted) {
            completer.complete(bestText.isEmpty ? null : bestText);
          }
        },
      );

      final result = await completer.future.timeout(
        listenFor + pauseFor + const Duration(seconds: 1),
        onTimeout: () => bestText.isEmpty ? null : bestText,
      );

      await _stt.stop();
      return result;
    } catch (e) {
      debugPrint('[VoiceCommandDatasource] listenOnce error: $e');
      return null;
    }
  }
}
