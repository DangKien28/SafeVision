import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:safe_vision_app/core/utils/image_converter.dart';

void main() {
  // LetterboxResult

  group('LetterboxResult', () {
    test('stores all data fields', () {
      final tensor = Float32List(640 * 640 * 3);
      final result = LetterboxResult(
        inputTensor: tensor,
        scale: 2.0,
        padLeft: 0.0625,
        padTop: 0.0,
        origWidth: 240,
        origHeight: 320,
      );

      expect(result.inputTensor, same(tensor));
      expect(result.scale, 2.0);
      expect(result.padLeft, 0.0625);
      expect(result.padTop, 0.0);
      expect(result.origWidth, 240);
      expect(result.origHeight, 320);
    });
  });

  // letterboxAndNormalize

  group('ImageConverter.letterboxAndNormalize', () {
    const inputSize = 640;

    img.Image makeImage(int w, int h, {int r = 128, int g = 64, int b = 32}) {
      final image = img.Image(width: w, height: h);
      img.fill(image, color: img.ColorRgb8(r, g, b));
      return image;
    }

    test('portrait image - correct scale and horizontal padding', () {
      final image = makeImage(240, 320);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      // Longest side = 320, so scale = 640/320 = 2.0.
      expect(result.scale, closeTo(2.0, 0.001));
      expect(result.origWidth, 240);
      expect(result.origHeight, 320);
      // The shorter side (width) is padded horizontally.
      expect(result.padLeft, closeTo(0.125, 0.002));
      expect(result.padTop, closeTo(0.0, 0.002));
    });

    test('landscape image - correct scale and vertical padding', () {
      final image = makeImage(320, 240);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      expect(result.scale, closeTo(2.0, 0.001));
      expect(result.padLeft, closeTo(0.0, 0.002));
      // The shorter side (height) is padded vertically.
      expect(result.padTop, closeTo(0.125, 0.002));
    });

    test('square image - no padding', () {
      final image = makeImage(320, 320);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      expect(result.scale, closeTo(2.0, 0.001));
      expect(result.padLeft, closeTo(0.0, 0.002));
      expect(result.padTop, closeTo(0.0, 0.002));
    });

    test('image already inputSize - scale=1.0 and no padding', () {
      final image = makeImage(640, 640);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      expect(result.scale, closeTo(1.0, 0.001));
      expect(result.padLeft, closeTo(0.0, 0.002));
      expect(result.padTop, closeTo(0.0, 0.002));
    });

    test('output tensor has size inputSize x inputSize x 3', () {
      final image = makeImage(100, 200);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      expect(result.inputTensor.length, equals(inputSize * inputSize * 3));
    });

    test('tensor values are normalized in range [0.0, 1.0]', () {
      final image = makeImage(320, 240, r: 255, g: 0, b: 128);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      for (final v in result.inputTensor) {
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });

    test('padding area is filled with gray ≈ 114/255', () {
      // Landscape image: the first and last rows are vertical padding.
      final image = makeImage(320, 240, r: 255, g: 0, b: 0);
      final result = ImageConverter.letterboxAndNormalize(image, inputSize);

      const grayNorm = 114.0 / 255.0;
      // The first pixel in the top-left corner belongs to the padding area.
      expect(result.inputTensor[0], closeTo(grayNorm, 0.01));
    });
  });

  // unLetterboxBox

  group('ImageConverter.unLetterboxBox', () {
    const inputSize = 640;

    test('centered bounding box is mapped to center of original image', () {
      // Setup: portrait image 240x320, scale = 2.0, padLeft = 0.125.
      // The box is centered in model output space.
      final box = ImageConverter.unLetterboxBox(
        cx: 0.5,
        cy: 0.5,
        bw: 0.5,
        bh: 0.5,
        padLeft: 0.125,
        padTop: 0.0,
        scale: 2.0,
        origWidth: 240,
        origHeight: 320,
        inputSize: inputSize,
      );

      expect(box.left, closeTo(0.167, 0.01));
      expect(box.top, closeTo(0.25, 0.01));
      expect(box.width, closeTo(0.667, 0.01));
      expect(box.height, closeTo(0.5, 0.01));
    });

    test('out of bounds box is clamped into [0.0, 1.0]', () {
      final box = ImageConverter.unLetterboxBox(
        cx: 0.0,
        cy: 0.5,
        bw: 0.1,
        bh: 0.3,
        padLeft: 0.125,
        padTop: 0.0,
        scale: 2.0,
        origWidth: 240,
        origHeight: 320,
        inputSize: inputSize,
      );

      expect(box.left, greaterThanOrEqualTo(0.0));
      expect(box.top, greaterThanOrEqualTo(0.0));
      expect(box.width, greaterThanOrEqualTo(0.0));
      expect(box.height, greaterThanOrEqualTo(0.0));
    });

    test('full box (1.0x1.0) is mapped to cover the entire original image', () {
      final box = ImageConverter.unLetterboxBox(
        cx: 0.5,
        cy: 0.5,
        bw: 1.0,
        bh: 1.0,
        padLeft: 0.0,
        padTop: 0.0,
        scale: 2.0,
        origWidth: 320,
        origHeight: 320,
        inputSize: inputSize,
      );

      expect(box.left, closeTo(0.0, 0.01));
      expect(box.top, closeTo(0.0, 0.01));
      expect(box.width, closeTo(1.0, 0.01));
      expect(box.height, closeTo(1.0, 0.01));
    });

    test('output values always inside [0.0, 1.0] even if input exceeds range',
        () {
      final box = ImageConverter.unLetterboxBox(
        cx: 1.5,
        cy: 1.5,
        bw: 2.0,
        bh: 2.0,
        padLeft: 0.0,
        padTop: 0.0,
        scale: 1.0,
        origWidth: 100,
        origHeight: 100,
        inputSize: inputSize,
      );

      expect(box.left, lessThanOrEqualTo(1.0));
      expect(box.top, lessThanOrEqualTo(1.0));
      expect(box.width, lessThanOrEqualTo(1.0));
      expect(box.height, lessThanOrEqualTo(1.0));
      expect(box.left, greaterThanOrEqualTo(0.0));
      expect(box.top, greaterThanOrEqualTo(0.0));
    });
  });

  // convertYuv420

  group('ImageConverter.convertYuv420', () {
    /// Creates synthetic planar YUV420 planes with Y=235 (bright) and
    /// UV=128 (neutral).
    (List<Uint8List>, List<int>, List<int>) makeYuvPlanes(int w, int h) {
      final y = Uint8List(w * h)..fillRange(0, w * h, 235);
      final uSize = (w ~/ 2) * (h ~/ 2);
      final u = Uint8List(uSize)..fillRange(0, uSize, 128);
      final v = Uint8List(uSize)..fillRange(0, uSize, 128);

      return ([y, u, v], [w, w ~/ 2, w ~/ 2], [1, 1, 1]);
    }

    test('output image has correct dimensions', () {
      const w = 8, h = 8;
      final (planes, rowStrides, pixelStrides) = makeYuvPlanes(w, h);

      final result =
          ImageConverter.convertYuv420(planes, rowStrides, pixelStrides, w, h);

      expect(result.width, w);
      expect(result.height, h);
    });

    test('neutral UV (128, 128) produces bright gray pixel from Y value', () {
      const w = 4, h = 4;
      final (planes, rowStrides, pixelStrides) = makeYuvPlanes(w, h);

      final result =
          ImageConverter.convertYuv420(planes, rowStrides, pixelStrides, w, h);

      // Y=235 with neutral UV should produce a bright near-white pixel.
      final pixel = result.getPixel(0, 0);
      expect(pixel.r, greaterThan(200));
      expect(pixel.g, greaterThan(200));
      expect(pixel.b, greaterThan(200));
    });

    test('out of bounds coordinates do not cause crash', () {
      final y = Uint8List(4)..fillRange(0, 4, 128);
      final u = Uint8List(1)..fillRange(0, 1, 128);
      final v = Uint8List(1)..fillRange(0, 1, 128);

      expect(
        () => ImageConverter.convertYuv420(
          [y, u, v],
          [4, 2, 2],
          [1, 1, 1],
          4,
          4,
        ),
        returnsNormally,
      );
    });
  });

  // Letterbox round-trip consistency

  group('Letterbox to unLetterbox round-trip consistency', () {
    test('coordinates after unLetterbox from letterbox result remain in [0, 1]',
        () {
      const inputSize = 640;

      final image = img.Image(width: 240, height: 320);
      img.fill(image, color: img.ColorRgb8(100, 150, 200));

      final lb = ImageConverter.letterboxAndNormalize(image, inputSize);

      final box = ImageConverter.unLetterboxBox(
        cx: 0.5,
        cy: 0.5,
        bw: 0.3,
        bh: 0.4,
        padLeft: lb.padLeft,
        padTop: lb.padTop,
        scale: lb.scale,
        origWidth: lb.origWidth,
        origHeight: lb.origHeight,
        inputSize: inputSize,
      );

      expect(box.left, inInclusiveRange(0.0, 1.0));
      expect(box.top, inInclusiveRange(0.0, 1.0));
      expect(box.width, inInclusiveRange(0.0, 1.0));
      expect(box.height, inInclusiveRange(0.0, 1.0));

      expect(box.left + box.width, lessThanOrEqualTo(1.0 + 1e-9));
      expect(box.top + box.height, lessThanOrEqualTo(1.0 + 1e-9));
    });
  });
}
