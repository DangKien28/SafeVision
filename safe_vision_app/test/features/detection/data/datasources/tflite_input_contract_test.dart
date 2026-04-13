import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:safe_vision_app/core/utils/image_converter.dart';

void main() {
  group('TFLite input contract', () {
    test('Float32List is inferred as rank-1 by tflite_flutter', () {
      final input = Float32List(640 * 640 * 3);

      expect(Tensor.computeShapeOf(input), [input.length]);
    });

    test('letterboxed tensor exposes a raw byte buffer for stable input copy',
        () {
      final yPlane = Uint8List.fromList([
        235,
        235,
        235,
        235,
        235,
        235,
        235,
        235,
        235,
        235,
        235,
        235,
        235,
        235,
        235,
        235,
      ]);
      final uPlane = Uint8List.fromList([128, 128, 128, 128]);
      final vPlane = Uint8List.fromList([128, 128, 128, 128]);

      final result = ImageConverter.yuvToLetterboxedFloat32(
        planes: [yPlane, uPlane, vPlane],
        rowStrides: [4, 2, 2],
        pixelStrides: [1, 1, 1],
        srcWidth: 4,
        srcHeight: 4,
        inputSize: 4,
        rotationDegrees: 0,
      );

      expect(result.inputTensor.length, 4 * 4 * 3);
      expect(
        result.inputBuffer.lengthInBytes,
        result.inputTensor.length * Float32List.bytesPerElement,
      );
      expect(
        result.inputBuffer.asFloat32List()[0],
        closeTo(result.inputTensor[0], 0.0001),
      );
    });
  });
}
