import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import '../../../../core/config/detection_config.dart';
import '../../../../core/models/camera_frame.dart';
import 'detection_local_datasource.dart';

class MlKitDetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  MlKitDetectionLocalDatasourceImpl(this._detectionConfig);

  final DetectionConfig _detectionConfig;
  ObjectDetector? _detector;
  bool _isBusy = false;

  @override
  Future<void> loadModel() async {
    _detector ??= ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> runInference(
    CameraFrame frame, {
    required int rotationDegrees,
  }) async {
    if (_detector == null || _isBusy) return [];

    _isBusy = true;
    try {
      final input = _toInputImage(frame, rotationDegrees);
      final detected = await _detector!.processImage(input);
      return _mapDetectedObjects(detected, frame.width, frame.height);
    } catch (e) {
      debugPrint('[MlKitDatasource] runInference error: $e');
      return [];
    } finally {
      _isBusy = false;
    }
  }

  @override
  Future<void> closeModel() async {
    final detector = _detector;
    _detector = null;
    if (detector != null) {
      await detector.close();
    }
    _isBusy = false;
  }

  InputImage _toInputImage(CameraFrame frame, int rotationDegrees) {
    final bytesBuilder = BytesBuilder(copy: false);
    for (final plane in frame.planes) {
      bytesBuilder.add(plane);
    }

    return InputImage.fromBytes(
      bytes: bytesBuilder.takeBytes(),
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: _rotationFromDegrees(rotationDegrees),
        format: InputImageFormat.yuv_420_888,
        bytesPerRow: frame.rowStrides.first,
      ),
    );
  }

  List<Map<String, dynamic>> _mapDetectedObjects(
    List<DetectedObject> detectedObjects,
    int width,
    int height,
  ) {
    final minConfidence = _detectionConfig.confidenceThreshold;
    final maxDetections = _detectionConfig.maxDetections;

    final mapped = detectedObjects.map((obj) {
      final bestLabel = obj.labels.isEmpty
          ? null
          : (obj.labels..sort((a, b) => b.confidence.compareTo(a.confidence)))
              .first;

      final confidence = bestLabel?.confidence ?? 0.5;
      final label =
          (bestLabel?.text.isNotEmpty ?? false) ? bestLabel!.text : 'doi_tuong';

      final left = (obj.boundingBox.left / width).clamp(0.0, 1.0);
      final top = (obj.boundingBox.top / height).clamp(0.0, 1.0);
      final right = (obj.boundingBox.right / width).clamp(0.0, 1.0);
      final bottom = (obj.boundingBox.bottom / height).clamp(0.0, 1.0);
      final boxWidth = (right - left).clamp(0.0, 1.0);
      final boxHeight = (bottom - top).clamp(0.0, 1.0);

      return <String, dynamic>{
        'label': label,
        'confidence': confidence,
        'left': left,
        'top': top,
        'width': boxWidth,
        'height': boxHeight,
      };
    }).where((m) {
      final confidence = (m['confidence'] as num).toDouble();
      final area = (m['width'] as double) * (m['height'] as double);
      return confidence >= minConfidence && area > 0;
    }).toList()
      ..sort(
        (a, b) =>
            (b['confidence'] as double).compareTo(a['confidence'] as double),
      );

    if (mapped.length <= maxDetections) return mapped;
    return mapped.take(maxDetections).toList(growable: false);
  }

  InputImageRotation _rotationFromDegrees(int degrees) {
    switch (degrees) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      case 0:
      default:
        return InputImageRotation.rotation0deg;
    }
  }
}
