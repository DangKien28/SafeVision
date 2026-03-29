import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// Dịch vụ Text-to-Speech tiếng Việt với hàng đợi + cooldown chống lặp
class TtsService {
  final FlutterTts _tts = FlutterTts();

  bool _isSpeaking = false;
  final List<String> _queue = [];

  /// Cooldown: không đọc cùng chuỗi trong vòng X ms
  static const int _cooldownMs = 3000;
  final Map<String, DateTime> _lastSpoken = {};

  // ── Khởi tạo ──────────────────────────────────────────────
  Future<void> initialize({
    String language   = 'vi-VN',
    double speechRate = 0.50,
    double pitch      = 1.00,
    double volume     = 1.00,
  }) async {
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(speechRate);
    await _tts.setPitch(pitch);
    await _tts.setVolume(volume);

    _tts.setStartHandler(()      { _isSpeaking = true; });
    _tts.setCompletionHandler(() { _isSpeaking = false; _processQueue(); });
    _tts.setCancelHandler(()    { _isSpeaking = false; _queue.clear(); });
    _tts.setErrorHandler((_)    { _isSpeaking = false; _processQueue(); });
  }

  // ── API công khai ──────────────────────────────────────────

  /// Đọc cảnh báo (có cooldown, có queue)
  Future<void> speakWarning(String text) async {
    final now  = DateTime.now();
    final last = _lastSpoken[text];
    if (last != null &&
        now.difference(last).inMilliseconds < _cooldownMs) {
      return; // Bỏ qua nếu vừa đọc
    }
    _lastSpoken[text] = now;
    _enqueue(text);
  }

  /// Đọc ngay lập tức, xóa queue (dùng cho cảnh báo khẩn)
  Future<void> speakImmediate(String text) async {
    await _tts.stop();
    _queue.clear();
    _isSpeaking = false;
    await _speak(text);
  }

  Future<void> stop() async {
    _queue.clear();
    await _tts.stop();
    _isSpeaking = false;
  }

  Future<void> pause() async => _tts.pause();

  bool get isSpeaking => _isSpeaking;

  void dispose() => _tts.stop();

  // ── Nội bộ ────────────────────────────────────────────────

  void _enqueue(String text) {
    if (!_queue.contains(text)) _queue.add(text);
    if (!_isSpeaking) _processQueue();
  }

  void _processQueue() {
    if (_queue.isEmpty || _isSpeaking) return;
    _speak(_queue.removeAt(0));
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    _isSpeaking = true;
    await _tts.speak(text);
  }
}