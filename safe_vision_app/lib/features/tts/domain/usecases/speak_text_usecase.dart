import 'package:flutter_tts/flutter_tts.dart';

class SpeakTextUseCase {
  final FlutterTts _flutterTts = FlutterTts();

  SpeakTextUseCase() {
    _initTts();
  }

  Future<void> _initTts() async {
    // Thiết lập ngôn ngữ Tiếng Việt
    await _flutterTts.setLanguage("vi-VN");
    // Tốc độ đọc (0.5 là vừa phải, có thể chỉnh nhanh hơn cho người khiếm thị quen nghe)
    await _flutterTts.setSpeechRate(0.5); 
    // Độ cao giọng
    await _flutterTts.setPitch(1.0);
  }

  Future<void> execute(String text) async {
    print('🔊 Đang đọc: "$text"');
    await _flutterTts.speak(text);
  }
}