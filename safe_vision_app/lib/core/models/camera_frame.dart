import 'dart:typed_data';

/// Immutable snapshot of one camera frame with plane bytes already copied.
///
/// This type is transport-only and does not depend on the camera plugin, which
/// keeps domain contracts decoupled from infrastructure classes such as
/// `CameraImage` and `CameraService`.
class CameraFrame {
  final List<Uint8List> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;
  final int width;
  final int height;

  const CameraFrame({
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
    required this.width,
    required this.height,
  });
}
