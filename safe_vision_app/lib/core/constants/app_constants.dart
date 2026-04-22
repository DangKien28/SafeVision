class AppConstants {
  AppConstants._();

  static const String modelFileName = 'assets/models/yolov8n_safevision.tflite';
  static const String labelsFileName = 'assets/models/labels.txt';

  // ── Detection thresholds ────────────────────────────────────────────────
  // FIX-PERF-1: Tăng confidence từ 0.50 → 0.60 để giảm false positive.
  // Với YOLOv8n (nano model nhỏ), 0.50 quá thấp nên model báo sai nhiều.
  static const double confidenceThreshold = 0.60;
  static const double iouThreshold = 0.45;
  static const int maxDetections = 10;
  static const int maxClassesPerBox = 2;

  // ── Pipeline tuning ─────────────────────────────────────────────────────
  static const int inputSize = 320;

  // FIX-PERF-2: Giảm từ 180ms → 50ms để bỏ throttle nhân tạo.
  // Giá trị 180ms vô tình giới hạn toàn pipeline ở ~5.5fps ngay cả khi
  // inference GPU nhanh hơn nhiều (20-50ms). Giờ pipeline có thể đạt
  // tốc độ thực sự của phần cứng.
  static const int busyFrameReplacementMinIntervalMs = 50;
  static const int inferenceThreads = 4;

  static const int inferenceTimeoutMs = 5000;

  // FIX-PERF-3: Tăng ngưỡng lỗi liên tiếp từ 1 → 3 (GPU) và 2 → 5 (CPU).
  // Giá trị cũ quá thấp: GPU thường fail lần đầu do warmup, sau đó ổn định.
  // Với maxConsecutiveAcceleratedFailures=1, một lần warmup fail là đủ để
  // toàn phiên chạy bằng CPU (200-400ms/frame thay vì 20-50ms GPU).
  static const int maxConsecutiveAcceleratedFailures = 3;
  static const int maxConsecutiveCpuFailures = 5;

  static const bool yoloChannelsFirst = true;
  static const bool yoloCoordinatesNormalized = true;
  static const bool yoloOutputLogits = false;
  static const bool yoloHasObjectness = false;

  // ── Object tracking ─────────────────────────────────────────────────────
  // FIX-TRACK-1: Giảm alpha từ 0.65 → 0.50.
  // Alpha 0.65 được thiết kế cho 20+fps. Ở 5fps, mỗi frame cách 200ms nên
  // vị trí box nhảy rõ ràng mắt người. Alpha 0.50 cho trọng số bằng nhau
  // giữa vị trí cũ và mới → smoother ở FPS thấp.
  static const double trackingSmoothingAlpha = 0.50;

  // FIX-TRACK-2: Giảm max age từ 1200ms → 800ms.
  // Track ảo tồn tại quá lâu (1.2s) gây UI lag khi object biến mất.
  // 800ms vẫn đủ để bridge qua vài frame bị drop.
  static const int trackingMaxAgeMs = 800;

  static const int trackingConfirmFrames = 2;
  static const int trackingMaxMissedFrames = 2;
  static const double trackingTentativeOpacity = 0.40;
  static const double trackingFadingOpacityFloor = 0.28;

  // ── Warning / danger thresholds ─────────────────────────────────────────
  static const double dangerousAreaThreshold = 0.10;
  static const double criticalDangerAreaThreshold = 0.15;
  static const double minRenderableBoxArea = 0.0008;
  static const double maxRenderableAspectRatio = 8.0;
  static const int warningStableVisibleFrames = 2;
  static const int dangerWarningStableVisibleFrames = 2;
  static const int warningRepeatMs = 3000;
  static const int dangerWarningRepeatMs = 1200;
  static const int warningSemanticRepeatMs = 4500;
  static const int warningStateChangeMinMs = 2500;

  // ── TTS ─────────────────────────────────────────────────────────────────
  static const int ttsCooldownMs = 3000;
  static const int ttsMinInterruptMs = 900;
  static const double ttsSpeechRate = 0.50;
  static const double ttsPitch = 1.00;
  static const double ttsVolume = 1.00;
  static const String ttsLanguage = 'vi-VN';

  // Giảm theo trackingMaxAgeMs để frame cũ không được dùng khi track đã chết
  static const int latestFrameMaxAgeMs = 800;
}
