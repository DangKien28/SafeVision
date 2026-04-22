class AppConstants {
  AppConstants._();

  static const String modelFileName = 'assets/models/yolov8n_safevision.tflite';
  static const String labelsFileName = 'assets/models/labels.txt';

  static const double confidenceThreshold = 0.30;
  static const double iouThreshold = 0.45;
  static const int maxDetections = 10;

  static const int inputSize = 640;
  static const int activeInferenceFps = 16;
  static const int inferenceThreads = 4;

  static const int inferenceTimeoutMs = 5000;

  static const int warmupTimeoutMs = 1200;

  static const bool yoloOutputLogits = false;
  static const bool yoloHasObjectness = false;

  static const double trackingSmoothingAlpha = 0.65;
  static const int trackingMaxAgeMs = 400;

  static const double dangerousAreaThreshold = 0.10;

  // Basic display mode defaults (beginner-friendly simplified indicators).
  static const bool basicModeDefaultEnabled = false;
  static const int basicModeMaxIndicators = 3;
  static const int basicModeMinConsecutiveFrames = 2;
  static const double basicModeMinRenderableBoxArea = 0.003;

  // Rendering constraints for indicator painter.
  static const double minRenderableBoxArea = 0.001;
  static const double maxRenderableAspectRatio = 4.0;

  static const int ttsCooldownMs = 3000;
  static const double ttsSpeechRate = 0.50;
  static const double ttsPitch = 1.00;
  static const double ttsVolume = 1.00;
  static const String ttsLanguage = 'vi-VN';

  static const int latestFrameMaxAgeMs = 4000;
}
