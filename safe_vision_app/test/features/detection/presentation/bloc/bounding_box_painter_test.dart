import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/object_indicator_painter.dart';

Future<int> alphaAt({
  required ObjectIndicatorPainter painter,
  required Size size,
  required Offset sample,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);

  final image = await recorder
      .endRecording()
      .toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(bytes, isNotNull);

  final width = size.width.toInt();
  final height = size.height.toInt();
  final x = sample.dx.toInt().clamp(0, width - 1);
  final y = sample.dy.toInt().clamp(0, height - 1);
  final alphaIndex = (y * width + x) * 4 + 3;
  return bytes!.getUint8(alphaIndex);
}

void main() {
  // Reset the static cache between groups so TextPainter state from
  // one group does not affect the next one.
  tearDown(() {
    ObjectIndicatorPainter.clearCacheForTesting();
  });

  // dispose() and TextPainter memory management

  group('ObjectIndicatorPainter.dispose() xóa bộ nhớ đệm TextPainter', () {
    testWidgets('dispose() runs without crash and correctly clears labels',
        (tester) async {
      final painter = ObjectIndicatorPainter(
        boxes: [
          const SmoothedBox(
            left: 0.1,
            top: 0.1,
            width: 0.3,
            height: 0.4,
            label: 'nguoi_di_bo',
            trackId: 1,
            missedFrames: 0,
          ),
          const SmoothedBox(
            left: 0.5,
            top: 0.2,
            width: 0.2,
            height: 0.3,
            label: 'xe',
            trackId: 2,
            missedFrames: 0,
          ),
        ],
        version: 1,
      );

      // Paint once to populate the TextPainter cache with 'nguoi_di_bo' and 'xe'.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(painter: painter),
            ),
          ),
        ),
      );

      expect(() => painter.dispose(), returnsNormally,
          reason: 'dispose() phải xóa TextPainter cache mà không crash');
    });

    testWidgets('dispose() with multiple labels does not leak memory',
        (tester) async {
      final boxes = List.generate(
        10,
        (i) => SmoothedBox(
          left: i * 0.05,
          top: 0.1,
          width: 0.04,
          height: 0.04,
          label: 'cay',
          trackId: i,
          missedFrames: 0,
        ),
      );

      final painter = ObjectIndicatorPainter(boxes: boxes, version: 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(child: CustomPaint(painter: painter)),
          ),
        ),
      );

      expect(() => painter.dispose(), returnsNormally);
    });
  });

  // Paint objects do not share state between painters

  group('Paint theo từng instance — không dùng chung mutable state', () {
    testWidgets('subsequent frame with different label does not affect color',
        (tester) async {
      final boxes1 = [
        const SmoothedBox(
          left: 0.1,
          top: 0.1,
          width: 0.3,
          height: 0.4,
          label: 'nguoi_di_bo',
          trackId: 1,
          missedFrames: 0,
        ),
      ];
      final boxes2 = [
        const SmoothedBox(
          left: 0.5,
          top: 0.5,
          width: 0.2,
          height: 0.2,
          label: 'xe',
          trackId: 2,
          missedFrames: 0,
        ),
      ];

      final painter1 = ObjectIndicatorPainter(boxes: boxes1, version: 1);
      await tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: SizedBox.expand(child: CustomPaint(painter: painter1)))),
      );
      expect(tester.takeException(), isNull,
          reason: 'Khung hình 1 không được ném lỗi');

      final painter2 = ObjectIndicatorPainter(boxes: boxes2, version: 2);
      await tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: SizedBox.expand(child: CustomPaint(painter: painter2)))),
      );
      expect(tester.takeException(), isNull,
          reason: 'Frame 2 is not affected by Paint state of frame 1');
    });

    testWidgets('missedFrames opacity áp dụng độc lập cho từng box',
        (tester) async {
      final boxes = [
        const SmoothedBox(
          left: 0.1,
          top: 0.1,
          width: 0.3,
          height: 0.4,
          label: 'xe',
          trackId: 1,
          missedFrames: 0,
        ),
        const SmoothedBox(
          left: 0.5,
          top: 0.5,
          width: 0.2,
          height: 0.2,
          label: 'balo',
          trackId: 2,
          missedFrames: 2,
        ),
      ];

      final painter = ObjectIndicatorPainter(boxes: boxes, version: 1);
      await tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: SizedBox.expand(child: CustomPaint(painter: painter)))),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // shouldRepaint uses an O(1) version counter

  group('shouldRepaint dùng bộ đếm version O(1)', () {
    test('same version -> does not repaint', () {
      final boxes = [
        const SmoothedBox(
          left: 0.1,
          top: 0.1,
          width: 0.3,
          height: 0.4,
          label: 'nguoi_di_bo',
          trackId: 1,
          missedFrames: 0,
        ),
      ];
      final painter1 = ObjectIndicatorPainter(boxes: boxes, version: 5);
      final painter2 = ObjectIndicatorPainter(boxes: boxes, version: 5);

      expect(painter1.shouldRepaint(painter2), isFalse,
          reason: 'Cùng version thì shouldRepaint = false, O(1)');
    });

    test('version khác → vẽ lại', () {
      const boxes = [
        SmoothedBox(
          left: 0.1,
          top: 0.1,
          width: 0.3,
          height: 0.4,
          label: 'nguoi_di_bo',
          trackId: 1,
          missedFrames: 0,
        ),
      ];
      final painter1 = ObjectIndicatorPainter(boxes: boxes, version: 5);
      final painter2 = ObjectIndicatorPainter(boxes: boxes, version: 6);

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('mirrorHorizontal khác → vẽ lại bất kể version', () {
      final painter1 = ObjectIndicatorPainter(
          boxes: const [], mirrorHorizontal: false, version: 1);
      final painter2 = ObjectIndicatorPainter(
          boxes: const [], mirrorHorizontal: true, version: 1);

      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('same version and mirror flag -> does not repaint', () {
      final painter1 = ObjectIndicatorPainter(
          boxes: const [], mirrorHorizontal: false, version: 3);
      final painter2 = ObjectIndicatorPainter(
          boxes: const [], mirrorHorizontal: false, version: 3);

      expect(painter1.shouldRepaint(painter2), isFalse);
    });
  });

  // BoxTracker version counter

  group('Bộ đếm version của BoxTracker', () {
    DetectionObject makeDetection({
      String label = 'nguoi_di_bo',
      double left = 0.1,
      double w = 0.2,
      double h = 0.3,
    }) =>
        DetectionObject(
          label: label,
          confidence: 0.9,
          boundingBox: BoundingBox(left: left, top: 0.1, width: w, height: h),
        );

    test('version bắt đầu từ 0', () {
      final tracker = BoxTracker();
      expect(tracker.version, equals(0));
    });

    test('version increments after each update', () {
      final tracker = BoxTracker();
      tracker.update([makeDetection()]);
      expect(tracker.version, equals(1));
      tracker.update([makeDetection()]);
      expect(tracker.version, equals(2));
    });

    test('version tăng sau clear()', () {
      final tracker = BoxTracker();
      final vBefore = tracker.version;
      tracker.clear();
      expect(tracker.version, greaterThan(vBefore));
    });

    test('update rỗng vẫn tăng version', () {
      final tracker = BoxTracker();
      tracker.update([]);
      expect(tracker.version, equals(1));
    });
  });

  // Painter regression

  group('Kiểm thử hồi quy của ObjectIndicatorPainter', () {
    testWidgets('paints without error on empty list', (tester) async {
      final painter = ObjectIndicatorPainter(boxes: const [], version: 0);
      await tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: SizedBox.expand(child: CustomPaint(painter: painter)))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('toggling mirrorHorizontal does not crash', (tester) async {
      final painter = ObjectIndicatorPainter(
        boxes: const [
          SmoothedBox(
            left: 0.3,
            top: 0.3,
            width: 0.4,
            height: 0.4,
            label: 'xe',
            trackId: 1,
            missedFrames: 0,
          )
        ],
        mirrorHorizontal: true,
        version: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: SizedBox.expand(child: CustomPaint(painter: painter)))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('out of bounds box is clamped without crashing',
        (tester) async {
      final painter = ObjectIndicatorPainter(
        boxes: const [
          SmoothedBox(
            left: -0.1,
            top: -0.1,
            width: 1.5,
            height: 1.5,
            label: 'cay',
            trackId: 1,
            missedFrames: 0,
          ),
        ],
        version: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: SizedBox.expand(child: CustomPaint(painter: painter)))),
      );
      expect(tester.takeException(), isNull,
          reason:
              'Các box vượt biên phải được chặn trong phạm vi và không được crash');
    });

    test('left-zone object activates left edge indicator', () async {
      const size = Size(300, 300);
      const sample = Offset(66, 150);

      final leftZonePainter = ObjectIndicatorPainter(
        boxes: const [
          SmoothedBox(
            left: 0.05,
            top: 0.20,
            width: 0.20,
            height: 0.20,
            label: 'xe',
            trackId: 1,
            missedFrames: 0,
          ),
        ],
        animationValue: 0.3,
        version: 1,
      );
      final rightZonePainter = ObjectIndicatorPainter(
        boxes: const [
          SmoothedBox(
            left: 0.75,
            top: 0.20,
            width: 0.20,
            height: 0.20,
            label: 'xe',
            trackId: 2,
            missedFrames: 0,
          ),
        ],
        animationValue: 0.3,
        version: 1,
      );

      final leftAlpha =
          await alphaAt(painter: leftZonePainter, size: size, sample: sample);
      final rightAlpha =
          await alphaAt(painter: rightZonePainter, size: size, sample: sample);

      expect(leftAlpha, greaterThan(0));
      expect(leftAlpha, greaterThan(rightAlpha));
    });

    test('left-zone mirror mode still activates edge indicator', () async {
      const size = Size(300, 300);
      const sample = Offset(66, 150);

      final mirroredLeftZonePainter = ObjectIndicatorPainter(
        boxes: const [
          SmoothedBox(
            left: 0.05,
            top: 0.20,
            width: 0.20,
            height: 0.20,
            label: 'xe',
            trackId: 1,
            missedFrames: 0,
          ),
        ],
        mirrorHorizontal: true,
        animationValue: 0.3,
        version: 1,
      );
      final mirroredRightZonePainter = ObjectIndicatorPainter(
        boxes: const [
          SmoothedBox(
            left: 0.75,
            top: 0.20,
            width: 0.20,
            height: 0.20,
            label: 'xe',
            trackId: 2,
            missedFrames: 0,
          ),
        ],
        mirrorHorizontal: true,
        animationValue: 0.3,
        version: 1,
      );

      final leftAlpha = await alphaAt(
        painter: mirroredLeftZonePainter,
        size: size,
        sample: sample,
      );
      final rightAlpha = await alphaAt(
        painter: mirroredRightZonePainter,
        size: size,
        sample: sample,
      );

      expect(leftAlpha, greaterThan(0));
      expect(leftAlpha, greaterThan(rightAlpha));
    });
  });
}
