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
      expect(AppConstants.inferenceThreads, 2);
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
