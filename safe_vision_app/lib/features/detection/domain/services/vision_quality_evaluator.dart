import '../../../../core/models/camera_frame.dart';

class VisionQualityEvaluator {
  const VisionQualityEvaluator._();

  static double score(CameraFrame frame) {
    if (frame.planes.isEmpty || frame.planes.first.isEmpty) return 0;

    final yPlane = frame.planes.first;
    const step = 16;
    var sampled = 0;
    var sum = 0.0;
    var sumSq = 0.0;

    for (var i = 0; i < yPlane.length; i += step) {
      final v = yPlane[i].toDouble() / 255.0;
      sampled++;
      sum += v;
      sumSq += v * v;
    }

    if (sampled == 0) return 0;

    final mean = sum / sampled;
    final variance = (sumSq / sampled) - (mean * mean);
    final contrast = variance < 0 ? 0.0 : variance;

    final brightnessScore = 1.0 - ((mean - 0.5).abs() * 2.0);
    final contrastScore = (contrast * 12).clamp(0.0, 1.0);

    return (brightnessScore * 0.6 + contrastScore * 0.4).clamp(0.0, 1.0);
  }
}
