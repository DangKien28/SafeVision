import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/usecases/usecase.dart';

class TestUseCase implements UseCase<String, int> {
  @override
  Future<String> call(int params) async => 'result_$params';
}

void main() {
  group('NoParams', () {
    test('can be constructed', () {
      const params = NoParams();
      expect(params, isA<NoParams>());
    });

    test('const instances are identical', () {
      const p1 = NoParams();
      const p2 = NoParams();
      expect(identical(p1, p2), isTrue);
    });
  });

  group('UseCase', () {
    test('concrete implementation can be called', () async {
      final usecase = TestUseCase();
      final result = await usecase(42);
      expect(result, 'result_42');
    });
  });
}
