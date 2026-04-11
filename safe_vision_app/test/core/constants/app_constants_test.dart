import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/constants/app_constants.dart';

void main() {
  group('AppConstants', () {
    test('model file paths are set', () {
      expect(AppConstants.modelFileName, isNotEmpty);
      expect(
        AppConstants.modelFileName,
        'assets/models/yolov8n_safevision.tflite',
      );
    });

    test('labels file path is set', () {
      expect(AppConstants.labelsFileName, 'assets/models/labels.txt');
    });

    test('confidenceThreshold is reasonable', () {
      expect(AppConstants.confidenceThreshold, 0.30);
      expect(AppConstants.confidenceThreshold, greaterThan(0));
      expect(AppConstants.confidenceThreshold, lessThan(1));
    });

    test('iouThreshold is reasonable', () {
      expect(AppConstants.iouThreshold, 0.45);
      expect(AppConstants.iouThreshold, greaterThan(0));
      expect(AppConstants.iouThreshold, lessThan(1));
    });

    test('maxDetections is positive', () {
      expect(AppConstants.maxDetections, 10);
      expect(AppConstants.maxDetections, greaterThan(0));
    });

    test('inputSize is positive', () {
      expect(AppConstants.inputSize, 640);
      expect(AppConstants.inputSize, greaterThan(0));
    });

    test('activeInferenceFps is positive', () {
      expect(AppConstants.activeInferenceFps, 6);
    });

    test('inferenceThreads is positive', () {
      // 4 threads to span the big-core cluster on MTK big.LITTLE SoCs.
      expect(AppConstants.inferenceThreads, 4);
      expect(AppConstants.inferenceThreads, greaterThan(0));
    });

    test('inferenceTimeoutMs exceeds realistic CPU inference time', () {
      // Must be greater than measured CPU inference (~2640ms on this device).
      // Set to 4000ms for 50% headroom against thermal variance.
      expect(AppConstants.inferenceTimeoutMs, 4000);
      expect(AppConstants.inferenceTimeoutMs, greaterThan(2500));
    });

    test('warmupTimeoutMs is between NPU cold-init and NNAPI failure time', () {
      // Must reject NNAPI (3363ms actual) → warmup < 3363ms ✓
      // Must not false-trigger on NPU cold-init (~800ms) → warmup > 800ms ✓
      expect(AppConstants.warmupTimeoutMs, 1200);
      expect(AppConstants.warmupTimeoutMs, greaterThan(800));
      expect(AppConstants.warmupTimeoutMs,
          lessThan(AppConstants.inferenceTimeoutMs));
    });

    test('yoloOutputLogits is false', () {
      expect(AppConstants.yoloOutputLogits, isFalse);
    });

    test('yoloHasObjectness is false', () {
      expect(AppConstants.yoloHasObjectness, isFalse);
    });

    test('tracking constants are set', () {
      expect(AppConstants.trackingSmoothingAlpha, 0.65);
      expect(AppConstants.trackingMaxAgeMs, 400);
    });

    test('dangerousAreaThreshold is between 0 and 1', () {
      expect(AppConstants.dangerousAreaThreshold, 0.10);
      expect(AppConstants.dangerousAreaThreshold, greaterThan(0));
      expect(AppConstants.dangerousAreaThreshold, lessThan(1));
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