import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/core/usecases/usecase.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/close_model_usecase.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/detection_object_from_frame.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/load_model_usecase.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_bloc.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_event.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_state.dart';

class MockLoadModelUsecase extends Mock implements LoadModelUsecase {}

class MockCloseModelUsecase extends Mock implements CloseModelUsecase {}

class MockDetectFromFrame extends Mock implements DetectionObjectFromFrame {}

void main() {
  late MockLoadModelUsecase mockLoad;
  late MockCloseModelUsecase mockClose;
  late MockDetectFromFrame mockDetect;

  setUpAll(() {
    registerFallbackValue(const NoParams());
  });

  setUp(() {
    mockLoad = MockLoadModelUsecase();
    mockClose = MockCloseModelUsecase();
    mockDetect = MockDetectFromFrame();
  });

  DetectionBloc buildBloc() => DetectionBloc(
        loadModel: mockLoad,
        closeModel: mockClose,
        detectFromFrame: mockDetect,
        onWarning: (
            {required text, required immediate, required withVibration}) {},
      );

  group('Start → Stop → Start rapid sequence', () {
    test('closeModel always completes before loadModel on rapid restart',
        () async {
      final order = <String>[];

      when(() => mockClose.call(any())).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 50));
        order.add('close');
      });
      when(() => mockLoad.call(any())).thenAnswer((_) async {
        order.add('load');
      });

      final bloc = buildBloc();

      bloc.add(const DetectionStarted());
      await Future.delayed(const Duration(milliseconds: 10));

      bloc.add(const DetectionStopped());
      bloc.add(const DetectionStarted()); // rapid restart

      await Future.delayed(const Duration(milliseconds: 200));
      await bloc.close();

      // close must always precede the second load
      final closeIndex = order.lastIndexOf('close');
      final loadIndex = order.lastIndexOf('load');
      expect(closeIndex, lessThan(loadIndex),
          reason: 'closeModel must complete before the next loadModel call. '
              'Got order: $order');
    });

    blocTest<DetectionBloc, DetectionState>(
      'rapid Stop then Start emits correct state sequence',
      build: () {
        when(() => mockClose.call(any())).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 30));
        });
        when(() => mockLoad.call(any())).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const DetectionStarted());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const DetectionStopped());
        bloc.add(const DetectionStarted());
        await Future.delayed(const Duration(milliseconds: 150));
      },
      expect: () => [
        const DetectionLoading(),
        const DetectionModelReady(),
        const DetectionInitial(),
        const DetectionLoading(),
        const DetectionModelReady(),
      ],
    );
  });
}
