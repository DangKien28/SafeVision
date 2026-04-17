// Wraps the FlutterTts native plugin.  This class is excluded from the
// coverage requirement because FlutterTts cannot run in unit tests (no audio
// engine).  All business logic (cooldown, queue dedup) lives in TtsBloc and
// is covered by unit tests via TestableTtsService.
//
// Registered as a LazySingleton in injection_container.dart so initialize()
// is called at first use (post-runApp) rather than at app cold-start.
 
import 'package:flutter_tts/flutter_tts.dart';
 
import '../../../../core/constants/app_constants.dart';
 
class TtsService {
  TtsService();
 
  final FlutterTts _flutterTts = FlutterTts();
  bool _initialised = false;
  bool _isSpeaking = false;
 
  bool get isSpeaking => _isSpeaking;
 
  // ── Initialization ─────────────────────────────────────────────────────────
 
  /// Sets up the TTS engine with default Vietnamese locale and parameters.
  ///
  /// Accepts optional overrides so [ConfigureTtsUsecase] can reconfigure the
  /// engine after a language/rate change in Settings.
  Future<void> initialize({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  }) async {
    await _flutterTts.setLanguage(language ?? AppConstants.ttsLanguage);
    await _flutterTts.setSpeechRate(speechRate ?? AppConstants.ttsSpeechRate);
    await _flutterTts.setPitch(pitch ?? AppConstants.ttsPitch);
    await _flutterTts.setVolume(volume ?? AppConstants.ttsVolume);
 
    _flutterTts.setStartHandler(() => _isSpeaking = true);
    _flutterTts.setCompletionHandler(() => _isSpeaking = false);
    _flutterTts.setErrorHandler((_) => _isSpeaking = false);
 
    _initialised = true;
  }
 
  // ── Playback ───────────────────────────────────────────────────────────────
 
  /// Speaks [text] via the cooldown queue.  Returns true if the engine
  /// accepted the call.
  Future<bool> speakWarning(String text) async {
    if (!_initialised) await initialize();
    final result = await _flutterTts.speak(text);
    return result == 1;
  }
 
  /// Interrupts any in-progress speech and speaks [text] immediately.
  Future<bool> speakImmediate(String text) async {
    if (!_initialised) await initialize();
    await _flutterTts.stop();
    final result = await _flutterTts.speak(text);
    return result == 1;
  }
 
  Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
  }
 
  Future<void> pause() async {
    await _flutterTts.pause();
  }
}