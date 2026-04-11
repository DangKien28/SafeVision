class AppConstants {
  AppConstants._();

  static const String modelFileName = 'assets/models/yolov8n_safevision.tflite';
  static const String labelsFileName = 'assets/models/labels.txt';

  static const double confidenceThreshold = 0.30;
  static const double iouThreshold = 0.45;
  static const int maxDetections = 10;

  // FIX: Changed from 320 to 640 to match model export (config.py IMG_SIZE = 640).
  //
  // Root cause of the shape mismatch crash:
  //   Model was exported at 640×640. The YOLOv8 neck concatenates feature maps
  //   at stride 16, producing a spatial dimension of inputSize/16.
  //   With inputSize=320: 320/16 = 20
  //   With inputSize=640: 640/16 = 40
  //   The CONCATENATION node at index 107 expected 40 but received 20,
  //   causing: t->dims->data[d] != t0->dims->data[d] (20 != 40)
  //
  // Performance note: 640×640 input quadruples tensor size vs 320×320
  // (~4.9 MB vs ~1.2 MB Float32 per frame). At 6 FPS with NNAPI this is
  // acceptable on target devices, but monitor inference latency in PerfMonitor.
  // If latency exceeds the 167ms frame budget, consider re-exporting the model
  // at 320×320 instead of changing this constant.
  static const int inputSize = 640;

  static const int activeInferenceFps = 6;
  static const int inferenceThreads = 2;

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
