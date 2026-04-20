import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/detection_control_bar.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/confidence_score_display.dart';
import 'package:safe_vision_app/features/detection/presentation/widgets/object_indicator_painter.dart';

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

  group('DetectionControlBar', () {
    testWidgets('lays out without exceptions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: DetectionControlBar(
                    onStop: () {},
                    onSettings: () {},
                    onSwitchCamera: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Dừng'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ObjectIndicatorPainter

  group('ObjectIndicatorPainter', () {
    testWidgets('paints without error when box list is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomPaint(
                painter: ObjectIndicatorPainter(
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
                painter: ObjectIndicatorPainter(
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
                painter: ObjectIndicatorPainter(
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
      final a = ObjectIndicatorPainter(boxes: [
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
      final b = ObjectIndicatorPainter(boxes: [
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
      final painter = ObjectIndicatorPainter(boxes: []);
      expect(painter.shouldRepaint(ObjectIndicatorPainter(boxes: [])), isFalse);
    });
  });
}
