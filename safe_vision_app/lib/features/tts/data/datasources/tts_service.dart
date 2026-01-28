import 'package:flutter_tts/flutter_tts.dart';
import 'dart:io' show Platform;

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();

  Future<void> initTts() async {
    // Thiết lập ngôn ngữ và các thông số cơ bản
    await _flutterTts.setLanguage("vi-VN");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5); // 0.5 nghe sẽ tự nhiên hơn 1.0 trên Android
    await _flutterTts.setVolume(1.0);
    
    // Đảm bảo không lỗi bind engine trên Android 11+
    if (Platform.isAndroid) {
      await _flutterTts.setEngine("com.google.android.tts");
    }
  }

  Future<void> speak(String? text) async {
    if (text == null || text.isEmpty) return;

    // Đợi 1s để hệ thống Android sẵn sàng (Fix lỗi bound chậm)
    await Future.delayed(const Duration(milliseconds: 1000)); 

    print("LOG: TTS thực hiện nói -> $text");
    await _flutterTts.speak(text);
  }

  void stop() {
    _flutterTts.stop();
  }
}