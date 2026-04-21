import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/constants/app_constants.dart';

void main() {
  group('AppConstants', () {
    test('model file paths are set', () {
      expect(AppConstants.modelFileName,
          'assets/models/yolov8n_safevision.tflite');
      expect(AppConstants.labelsFileName, 'assets/models/labels.txt');
    });

    test('detection thresholds are sane', () {
      expect(AppConstants.confidenceThreshold, 0.45);
      expect(AppConstants.iouThreshold, 0.45);
      expect(AppConstants.maxDetections, 10);
      expect(AppConstants.maxClassesPerBox, 2);
    });

    test('runtime tuning values are configured', () {
      expect(AppConstants.inputSize, 640);
      expect(AppConstants.activeInferenceFps, 6);
      expect(AppConstants.busyFrameReplacementMinIntervalMs, 180);
      expect(AppConstants.inferenceThreads, 4);
      expect(AppConstants.inferenceTimeoutMs, 5000);
      expect(AppConstants.maxConsecutiveAcceleratedFailures, 1);
      expect(AppConstants.maxConsecutiveCpuFailures, 2);
    });

    test('YOLO flags match exported model behavior', () {
      expect(AppConstants.yoloOutputLogits, isFalse);
      expect(AppConstants.yoloHasObjectness, isFalse);
    });

    test('tracking and rendering guards are sane', () {
      expect(AppConstants.trackingSmoothingAlpha, 0.65);
      expect(AppConstants.trackingMaxAgeMs, 400);
      expect(AppConstants.dangerousAreaThreshold, 0.10);
      expect(AppConstants.minRenderableBoxArea, greaterThan(0));
      expect(AppConstants.maxRenderableAspectRatio, greaterThan(1));
      expect(AppConstants.latestFrameMaxAgeMs, 1200);
      expect(AppConstants.basicModeMaxIndicators, greaterThan(0));
      expect(AppConstants.basicModeMinRenderableBoxArea, greaterThan(0));
      expect(AppConstants.basicModeMinConsecutiveFrames, greaterThan(0));
      expect(AppConstants.basicModeDefaultEnabled, isTrue);
      expect(AppConstants.alertStabilityFrames, greaterThan(0));
      expect(AppConstants.alertDangerousCooldownMs, greaterThan(0));
      expect(AppConstants.lowVisibilityWarningCooldownMs, greaterThan(0));
      expect(
        AppConstants.lowVisibilityThreshold,
        inInclusiveRange(0.0, 1.0),
      );
    });

    test('TTS constants are set', () {
      expect(AppConstants.ttsCooldownMs, 3000);
      expect(AppConstants.ttsSpeechRate, 0.50);
      expect(AppConstants.ttsPitch, 1.00);
      expect(AppConstants.ttsVolume, 1.00);
      expect(AppConstants.ttsLanguage, 'vi-VN');
    });
  });
}
