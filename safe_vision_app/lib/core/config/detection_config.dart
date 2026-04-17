import 'package:safe_vision_app/core/constants/app_constants.dart';

class DetectionConfig {
  DetectionConfig({
    double? confidenceThreshold,
    double? iouThreshold,
    int? maxDetections,
  })  : _confidenceThreshold =
            confidenceThreshold ?? AppConstants.confidenceThreshold,
        _iouThreshold = iouThreshold ?? AppConstants.iouThreshold,
        _maxDetections = maxDetections ?? AppConstants.maxDetections;
 
  double _confidenceThreshold;
  double _iouThreshold;
  int    _maxDetections;
 
  double get confidenceThreshold => _confidenceThreshold;
  double get iouThreshold        => _iouThreshold;
  int    get maxDetections       => _maxDetections;
 
  void setConfidenceThreshold(double v) =>
      _confidenceThreshold = v.clamp(0.01, 0.99);
  void setIouThreshold(double v) =>
      _iouThreshold = v.clamp(0.01, 0.99);
  void setMaxDetections(int v) =>
      _maxDetections = v.clamp(1, 100);
}