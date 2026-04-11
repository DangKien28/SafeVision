// lib/core/constants/app_constants.dart

class AppConstants {
  AppConstants._();

  static const String modelFileName = 'assets/models/yolov8n_safevision.tflite';
  static const String labelsFileName = 'assets/models/labels.txt';

  static const double confidenceThreshold = 0.30;
  static const double iouThreshold = 0.45;
  static const int maxDetections = 10;

  static const int inputSize = 640;
  static const int activeInferenceFps = 6;
  static const int inferenceThreads = 4;

  static const int inferenceTimeoutMs = 4000;

  static const int warmupTimeoutMs = 1200;

  static const bool yoloOutputLogits = false;
  static const bool yoloHasObjectness = false;

  static const double trackingSmoothingAlpha = 0.65;
  static const int trackingMaxAgeMs = 400;

  static const double dangerousAreaThreshold = 0.10;

  static const int ttsCooldownMs = 3000;
  static const double ttsSpeechRate = 0.50;
  static const double ttsPitch = 1.00;
  static const double ttsVolume = 1.00;
  static const String ttsLanguage = 'vi-VN';
}