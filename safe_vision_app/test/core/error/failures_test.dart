import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/error/failures.dart';

void main() {
  group('ModelFailure', () {
    test('stores message', () {
      const f = ModelFailure('model error');
      expect(f.message, 'model error');
    });

    test('equality via Equatable', () {
      const f1 = ModelFailure('error');
      const f2 = ModelFailure('error');
      const f3 = ModelFailure('other');
      expect(f1, equals(f2));
      expect(f1, isNot(equals(f3)));
    });

    test('props contains message', () {
      const f = ModelFailure('msg');
      expect(f.props, [equals('msg')]);
    });
  });

  group('InferenceFailure', () {
    test('stores message and supports equality', () {
      const f1 = InferenceFailure('fail');
      const f2 = InferenceFailure('fail');
      expect(f1.message, 'fail');
      expect(f1, equals(f2));
    });
  });

  group('CameraFailure', () {
    test('stores message and supports equality', () {
      const f1 = CameraFailure('cam');
      const f2 = CameraFailure('cam');
      expect(f1.message, 'cam');
      expect(f1, equals(f2));
    });
  });

  group('PermissionFailure', () {
    test('stores message and supports equality', () {
      const f1 = PermissionFailure('perm');
      const f2 = PermissionFailure('perm');
      expect(f1.message, 'perm');
      expect(f1, equals(f2));
    });
  });

  group('UnknownFailure', () {
    test('stores message and supports equality', () {
      const f1 = UnknownFailure('unknown');
      const f2 = UnknownFailure('unknown');
      expect(f1.message, 'unknown');
      expect(f1, equals(f2));
    });
  });

  group('Failure cross-type inequality', () {
    test('different subtypes with same message are not equal', () {
      const model = ModelFailure('error');
      const inference = InferenceFailure('error');
      // Equatable compares runtime types too
      expect(model, isNot(equals(inference)));
    });
  });
}
