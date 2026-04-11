import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/config/detection_config.dart';
import 'package:safe_vision_app/core/constants/app_constants.dart';

void main() {
  late DetectionConfig config;

  setUp(() {
    config = DetectionConfig();
  });

  group('default values', () {
    test('confidenceThreshold defaults to AppConstants', () {
      expect(config.confidenceThreshold, AppConstants.confidenceThreshold);
    });

    test('iouThreshold defaults to AppConstants', () {
      expect(config.iouThreshold, AppConstants.iouThreshold);
    });

    test('maxDetections defaults to AppConstants', () {
      expect(config.maxDetections, AppConstants.maxDetections);
    });
  });

  group('custom constructor values', () {
    test('accepts custom values', () {
      final custom = DetectionConfig(
        confidenceThreshold: 0.50,
        iouThreshold: 0.60,
        maxDetections: 20,
      );
      expect(custom.confidenceThreshold, 0.50);
      expect(custom.iouThreshold, 0.60);
      expect(custom.maxDetections, 20);
    });
  });

  group('setConfidenceThreshold', () {
    test('sets normal value within range', () {
      config.setConfidenceThreshold(0.5);
      expect(config.confidenceThreshold, 0.5);
    });

    test('clamps value below 0.01', () {
      config.setConfidenceThreshold(-1.0);
      expect(config.confidenceThreshold, 0.01);
    });

    test('clamps value above 0.99', () {
      config.setConfidenceThreshold(5.0);
      expect(config.confidenceThreshold, 0.99);
    });

    test('clamps value to exactly 0.01', () {
      config.setConfidenceThreshold(0.01);
      expect(config.confidenceThreshold, 0.01);
    });

    test('clamps value to exactly 0.99', () {
      config.setConfidenceThreshold(0.99);
      expect(config.confidenceThreshold, 0.99);
    });
  });

  group('setIouThreshold', () {
    test('sets normal value within range', () {
      config.setIouThreshold(0.7);
      expect(config.iouThreshold, 0.7);
    });

    test('clamps value below 0.01', () {
      config.setIouThreshold(0.0);
      expect(config.iouThreshold, 0.01);
    });

    test('clamps value above 0.99', () {
      config.setIouThreshold(1.5);
      expect(config.iouThreshold, 0.99);
    });
  });

  group('setMaxDetections', () {
    test('sets normal value within range', () {
      config.setMaxDetections(50);
      expect(config.maxDetections, 50);
    });

    test('clamps value below 1', () {
      config.setMaxDetections(0);
      expect(config.maxDetections, 1);
    });

    test('clamps value below 1 (negative)', () {
      config.setMaxDetections(-5);
      expect(config.maxDetections, 1);
    });

    test('clamps value above 100', () {
      config.setMaxDetections(200);
      expect(config.maxDetections, 100);
    });
  });
}
