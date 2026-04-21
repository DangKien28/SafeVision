import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/confidence_score_display.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/bounding_box_painter.dart';

void main() {
  // ConfidenceScoreDisplay

  group('ConfidenceScoreDisplay', () {
    Widget buildWidget(List<DetectionObject> detections, {int maxItems = 5}) {
      return MaterialApp(
        home: Scaffold(
          body: ConfidenceScoreDisplay(
            detections: detections,
            maxItems: maxItems,
          ),
        ),
      );
    }

    DetectionObject makeDetection({
      String label = 'nguoi_di_bo',
      double confidence = 0.85,
      double left = 0.1,
      double top = 0.1,
      double width = 0.3,
      double height = 0.4,
    }) =>
        DetectionObject(
          label: label,
          confidence: confidence,
          boundingBox: BoundingBox(
            left: left,
            top: top,
            width: width,
            height: height,
          ),
        );

    testWidgets('Does not display content when detection is empty',
        (tester) async {
      await tester.pumpWidget(buildWidget([]));

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('nguoi_di_bo'), findsNothing);
    });

    testWidgets('displays label when a single object is detected',
        (tester) async {
      await tester.pumpWidget(buildWidget([makeDetection(label: 'xe')]));

      expect(find.textContaining('xe'), findsOneWidget);
    });

    testWidgets('displays full labels for multiple detected objects',
        (tester) async {
      final detections = [
        makeDetection(label: 'nguoi_di_bo', confidence: 0.9),
        makeDetection(label: 'xe', confidence: 0.8),
        makeDetection(label: 'balo', confidence: 0.7),
      ];
      await tester.pumpWidget(buildWidget(detections));

      expect(find.textContaining('nguoi_di_bo'), findsOneWidget);
      expect(find.textContaining('xe'), findsOneWidget);
      expect(find.textContaining('balo'), findsOneWidget);
    });

    testWidgets('displays the count of detected objects', (tester) async {
      await tester.pumpWidget(buildWidget([
        makeDetection(label: 'nguoi_di_bo'),
        makeDetection(label: 'balo'),
      ]));

      expect(find.textContaining('2'), findsWidgets);
    });

    testWidgets('displays confidence percentage', (tester) async {
      await tester.pumpWidget(buildWidget([
        makeDetection(label: 'nguoi_di_bo', confidence: 0.85),
      ]));

      expect(find.textContaining('85'), findsWidgets);
    });

    testWidgets('only displays up to maxItems quantity', (tester) async {
      const testMaxItems = 5;
      final detections = List.generate(
        10,
        (i) => makeDetection(label: 'cay', confidence: 0.5 + i * 0.01),
      );

      await tester.pumpWidget(buildWidget(detections, maxItems: testMaxItems));

      expect(find.byType(LinearProgressIndicator), findsNWidgets(testMaxItems));
    });

    testWidgets('long label does not cause overflow', (tester) async {
      await tester.pumpWidget(buildWidget([
        makeDetection(
            label: 'cau_thang_rat_dai_va_to_lon_de_kiem_tra_overflow'),
      ]));

      expect(tester.takeException(), isNull);
    });
  });

  // BoundingBoxPainter

  group('BoundingBoxPainter', () {
    testWidgets('paints without error when box list is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(
                painter: BoundingBoxPainter(
                  boxes: [],
                  mirrorHorizontal: false,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('paints without error with a single box', (tester) async {
      final smoothed = [
        SmoothedBox(
          left: 0.2,
          top: 0.2,
          width: 0.4,
          height: 0.5,
          label: 'nguoi_di_bo',
          trackId: 1,
          missedFrames: 0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(
                painter: BoundingBoxPainter(
                  boxes: smoothed,
                  mirrorHorizontal: false,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('mirror mode does not cause crash', (tester) async {
      final smoothed = [
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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(
                painter: BoundingBoxPainter(
                  boxes: smoothed,
                  mirrorHorizontal: true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    test('shouldRepaint returns true when box lists differ', () {
      final a = BoundingBoxPainter(boxes: [
        const SmoothedBox(
          left: 0.1,
          top: 0.1,
          width: 0.3,
          height: 0.4,
          label: 'ban',
          trackId: 1,
          missedFrames: 0,
        ),
      ]);
      final b = BoundingBoxPainter(boxes: [
        const SmoothedBox(
          left: 0.5,
          top: 0.5,
          width: 0.2,
          height: 0.2,
          label: 'cay',
          trackId: 2,
          missedFrames: 0,
        ),
      ]);

      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns false when box lists are identical', () {
      final painter = BoundingBoxPainter(boxes: []);
      expect(painter.shouldRepaint(BoundingBoxPainter(boxes: [])), isFalse);
    });
  });

  // BoxTracker

  group('BoxTracker', () {
    DetectionObject make({
      String label = 'nguoi_di_bo',
      double left = 0.1,
      double top = 0.1,
      double w = 0.3,
      double h = 0.4,
    }) =>
        DetectionObject(
          label: label,
          confidence: 0.9,
          boundingBox: BoundingBox(left: left, top: top, width: w, height: h),
        );

    test('returns empty list when updated with empty detections', () {
      final tracker = BoxTracker();
      expect(tracker.update([]), isEmpty);
    });

    test('new detection added to tracked list', () {
      final tracker = BoxTracker();
      final result = tracker.update([make(label: 'nguoi_di_bo')]);

      expect(result.length, 1);
      expect(result[0].label, 'nguoi_di_bo');
    });

    test('same object detected twice remains single track', () {
      final tracker = BoxTracker();
      tracker.update([make(label: 'nguoi_di_bo', left: 0.1)]);
      // The position shifts slightly but is still treated as the same track via IoU.
      final result = tracker.update([make(label: 'nguoi_di_bo', left: 0.12)]);

      expect(result.length, 1);
    });

    test('track is deleted after maxTrackAge if no longer detected', () {
      final tracker = BoxTracker();
      final start = DateTime(2026, 1, 1, 12, 0, 0);

      tracker.update([make(label: 'nguoi_di_bo')], now: start);
      final result = tracker.update(
        [],
        now: start.add(const Duration(milliseconds: 450)),
      );

      expect(result, isEmpty);
    });

    test('two different objects are tracked independently', () {
      final tracker = BoxTracker();
      final result = tracker.update([
        make(label: 'nguoi_di_bo', left: 0.1),
        make(label: 'xe', left: 0.6),
      ]);

      expect(result.length, 2);
      expect(result.map((b) => b.label).toSet(), {'nguoi_di_bo', 'xe'});
    });

    test('clear() empties the tracker', () {
      final tracker = BoxTracker();
      tracker.update([make()]);
      tracker.clear();
      expect(tracker.update([]), isEmpty);
    });

    test('new track starts with missedFrames = 0', () {
      final tracker = BoxTracker();
      final result = tracker.update([make(label: 'cay')]);

      expect(result.single.missedFrames, 0);
    });

    test('matched track will set missedFrames to 0 after update', () {
      final tracker = BoxTracker();
      final start = DateTime(2026, 1, 1, 12, 0, 0);

      tracker.update([make(label: 'ghe')], now: start);
      // One frame without detections sets missedFrames = 1.
      tracker.update([], now: start.add(const Duration(milliseconds: 100)));
      // When the detection returns, missedFrames resets to 0.
      final result = tracker.update(
        [make(label: 'ghe', left: 0.11)],
        now: start.add(const Duration(milliseconds: 200)),
      );

      expect(result.single.missedFrames, 0);
    });
  });
}
