class AppConstants {
  AppConstants._();

  // Model
  static const String modelFileName = 'assets/models/yolov8n_safevision.tflite';
  static const String labelsFileName = 'assets/models/labels.txt';

  // Detection
  static const double confidenceThreshold = 0.30;
  static const double iouThreshold = 0.45;
  static const int maxDetections = 10;
  static const int inputSize = 640; // YOLOv8 default

  // TTS
  static const int ttsCooldownMs = 3000;
  static const double ttsSpeechRate = 0.50;
  static const double ttsPitch = 1.00;
  static const double ttsVolume = 1.00;
  static const String ttsLanguage = 'vi-VN';
}
