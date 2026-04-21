import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/features/detection/data/models/bounding_box_model.dart';

void main() {
  group('BoundingBoxModel', () {
    test('constructor stores values', () {
      const model = BoundingBoxModel(
        left: 0.1,
        top: 0.2,
        width: 0.3,
        height: 0.4,
      );
      expect(model.left, 0.1);
      expect(model.top, 0.2);
      expect(model.width, 0.3);
      expect(model.height, 0.4);
    });

    group('fromMap', () {
      test('parses from Map with double values', () {
        final model = BoundingBoxModel.fromMap({
          'left': 0.1,
          'top': 0.2,
          'width': 0.3,
          'height': 0.4,
        });
        expect(model.left, 0.1);
        expect(model.top, 0.2);
        expect(model.width, 0.3);
        expect(model.height, 0.4);
      });

      test('parses from Map with int values', () {
        final model = BoundingBoxModel.fromMap({
          'left': 0,
          'top': 1,
          'width': 2,
          'height': 3,
        });
        expect(model.left, 0.0);
        expect(model.top, 1.0);
        expect(model.width, 2.0);
        expect(model.height, 3.0);
      });
    });

    group('fromTFLiteList', () {
      test('converts [top, left, bottom, right] to model', () {
        final model = BoundingBoxModel.fromTFLiteList([0.1, 0.2, 0.5, 0.6]);
        // top=0.1, left=0.2, bottom=0.5, right=0.6
        expect(model.top, 0.1);
        expect(model.left, 0.2);
        expect(model.width, closeTo(0.4, 1e-10)); // right - left
        expect(model.height, closeTo(0.4, 1e-10)); // bottom - top
      });

      test('handles int values in list', () {
        final model = BoundingBoxModel.fromTFLiteList([0, 0, 1, 1]);
        expect(model.top, 0.0);
        expect(model.left, 0.0);
        expect(model.width, 1.0);
        expect(model.height, 1.0);
      });
    });

    group('toEntity', () {
      test('converts to BoundingBox entity', () {
        const model = BoundingBoxModel(
          left: 0.1,
          top: 0.2,
          width: 0.3,
          height: 0.4,
        );
        final entity = model.toEntity();
        expect(entity.left, 0.1);
        expect(entity.top, 0.2);
        expect(entity.width, 0.3);
        expect(entity.height, 0.4);
      });
    });
  });
}
