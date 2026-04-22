import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/models/camera_frame.dart';

void main() {
  group('CameraFrame.detachPlaneData', () {
    test('wraps owned plane bytes into transferables', () {
      final frame = CameraFrame(
        planes: [
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([4, 5]),
          Uint8List.fromList([6]),
        ],
        rowStrides: const [3, 2, 1],
        pixelStrides: const [1, 1, 1],
        width: 3,
        height: 1,
      );

      final detached = frame.detachPlaneData();

      expect(detached, hasLength(3));
      expect(detached[0].materialize().asUint8List(), [1, 2, 3]);
      expect(detached[1].materialize().asUint8List(), [4, 5]);
      expect(detached[2].materialize().asUint8List(), [6]);
    });

    test('reuses transferables when frame already carries them', () {
      final transferables = [
        TransferableTypedData.fromList([
          Uint8List.fromList([7, 8])
        ]),
        TransferableTypedData.fromList([
          Uint8List.fromList([9])
        ]),
        TransferableTypedData.fromList([
          Uint8List.fromList([10, 11])
        ]),
      ];
      final frame = CameraFrame(
        transferablePlanes: transferables,
        rowStrides: const [2, 1, 2],
        pixelStrides: const [1, 1, 1],
        width: 2,
        height: 2,
      );

      final detached = frame.detachPlaneData();

      expect(identical(detached, transferables), isTrue);
      expect(detached[0].materialize().asUint8List(), [7, 8]);
      expect(detached[1].materialize().asUint8List(), [9]);
      expect(detached[2].materialize().asUint8List(), [10, 11]);
    });
  });
}
