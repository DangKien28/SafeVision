class AppConstants {
  AppConstants._();

  static const String modelFileName = 'assets/models/yolov8n_safevision.tflite';
  static const String labelsFileName = 'assets/models/labels.txt';

  static const double confidenceThreshold = 0.30;
  static const double iouThreshold = 0.45;
  static const int maxDetections = 10;
  static const int maxClassesPerBox = 2;

  static const int inputSize = 640;
  static const int activeInferenceFps = 6;
  static const int busyFrameReplacementMinIntervalMs = 180;
  static const int inferenceThreads = 4;

  static const int inferenceTimeoutMs = 5000;
  static const int maxConsecutiveAcceleratedFailures = 1;
  static const int maxConsecutiveCpuFailures = 2;

  static const bool yoloChannelsFirst = true;
  static const bool yoloCoordinatesNormalized = true;
  static const bool yoloOutputLogits = false;
  static const bool yoloHasObjectness = false;

  static const double trackingSmoothingAlpha = 0.65;
  static const int trackingMaxAgeMs = 400;

  static const double dangerousAreaThreshold = 0.10;
  static const double minRenderableBoxArea = 0.0008;
  static const double maxRenderableAspectRatio = 8.0;
  static const int warningStableVisibleFrames = 2;
  static const int warningRepeatMs = 3000;
  static const int dangerWarningRepeatMs = 1200;

  static const int ttsCooldownMs = 3000;
  static const double ttsSpeechRate = 0.50;
  static const double ttsPitch = 1.00;
  static const double ttsVolume = 1.00;
  static const String ttsLanguage = 'vi-VN';

  static const int latestFrameMaxAgeMs = 1200;
}
