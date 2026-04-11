import '../constants/app_constants.dart';

class DetectionConfig {
  double _confidenceThreshold;
  double _iouThreshold;
  int _maxDetections;

  DetectionConfig({
    double confidenceThreshold = AppConstants.confidenceThreshold,
    double iouThreshold = AppConstants.iouThreshold,
    int maxDetections = AppConstants.maxDetections,
  })  : _confidenceThreshold = confidenceThreshold,
        _iouThreshold = iouThreshold,
        _maxDetections = maxDetections;

  double get confidenceThreshold => _confidenceThreshold;
  double get iouThreshold => _iouThreshold;
  int get maxDetections => _maxDetections;

  void setConfidenceThreshold(double v) =>
      _confidenceThreshold = v.clamp(0.01, 0.99);

  void setIouThreshold(double v) => _iouThreshold = v.clamp(0.01, 0.99);

  void setMaxDetections(int v) => _maxDetections = v.clamp(1, 100);
}
