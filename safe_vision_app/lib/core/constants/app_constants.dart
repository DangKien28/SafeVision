abstract class AppConstants {
  AppConstants._();
 
  // ── Asset paths ─────────────────────────────────────────────────────────────
  static const String modelFileName  = 'assets/models/yolov8n_safevision.tflite';
  static const String labelsFileName = 'assets/models/labels.txt';
 
  // ── Detection ───────────────────────────────────────────────────────────────
  static const double confidenceThreshold    = 0.30;
  static const double iouThreshold           = 0.45;
  static const int    maxDetections          = 10;
  static const int    maxClassesPerBox       = 2;
  static const int    inputSize              = 640;
 
  // ── Inference runtime ────────────────────────────────────────────────────────
  static const int    activeInferenceFps                       = 6;
  static const int    busyFrameReplacementMinIntervalMs        = 180;
  static const int    inferenceThreads                         = 4;
  static const int    inferenceTimeoutMs                       = 5000;
  static const int    maxConsecutiveAcceleratedFailures        = 1;
  static const int    maxConsecutiveCpuFailures                = 2;
 
  // ── YOLO model flags ────────────────────────────────────────────────────────
  static const bool yoloOutputLogits   = false;
  static const bool yoloHasObjectness  = false;
 
  // ── Tracking & rendering ─────────────────────────────────────────────────────
  static const double trackingSmoothingAlpha    = 0.65;
  static const int    trackingMaxAgeMs          = 400;
  static const double dangerousAreaThreshold    = 0.10;
  static const double minRenderableBoxArea      = 0.0001;
  static const double maxRenderableAspectRatio  = 10.0;
  static const int    latestFrameMaxAgeMs       = 1200;
 
  // ── TTS ──────────────────────────────────────────────────────────────────────
  static const int    ttsCooldownMs   = 3000;
  static const double ttsSpeechRate   = 0.50;
  static const double ttsPitch        = 1.00;
  static const double ttsVolume       = 1.00;
  static const String ttsLanguage     = 'vi-VN';
}