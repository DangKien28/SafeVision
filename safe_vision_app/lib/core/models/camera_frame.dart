import 'dart:isolate';
import 'dart:typed_data';

/// Immutable snapshot of one camera frame.
///
/// The frame may either own plain [Uint8List] plane bytes or carry
/// [TransferableTypedData] prepared inside the camera callback while the native
/// camera buffers are still valid. This keeps domain contracts decoupled from
/// infrastructure classes such as `CameraImage` and `CameraService`.
class CameraFrame {
  final List<Uint8List> planes;
  final List<TransferableTypedData> transferablePlanes;
  final List<int> rowStrides;
  final List<int> pixelStrides;
  final int width;
  final int height;

  CameraFrame({
    this.planes = const <Uint8List>[],
    this.transferablePlanes = const <TransferableTypedData>[],
    required this.rowStrides,
    required this.pixelStrides,
    required this.width,
    required this.height,
  })  : assert(
          planes.isNotEmpty || transferablePlanes.isNotEmpty,
          'CameraFrame requires plane data.',
        ),
        assert(
          planes.isEmpty || transferablePlanes.isEmpty,
          'CameraFrame must own either plain planes or transferable planes.',
        ),
        assert(
          (planes.isNotEmpty ? planes.length : transferablePlanes.length) ==
              rowStrides.length,
          'Plane data and row strides must have the same length.',
        ),
        assert(
          rowStrides.length == pixelStrides.length,
          'Row strides and pixel strides must have the same length.',
        );

  /// Returns plane payloads ready to cross an isolate boundary.
  ///
  /// When the frame already carries transferables from the camera callback,
  /// those are reused directly and no extra copy is performed on the UI
  /// isolate. Frames built in tests still work because raw [planes] are lazily
  /// converted here.
  List<TransferableTypedData> detachPlaneData() {
    if (transferablePlanes.isNotEmpty) return transferablePlanes;
    return [
      for (final plane in planes) TransferableTypedData.fromList([plane]),
    ];
  }
}
