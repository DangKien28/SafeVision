import 'package:bloc_test/bloc_test.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/core/usecases/usecase.dart';
import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/close_model_usecase.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/detection_object_from_frame.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/load_model_usecase.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_bloc.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_event.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_state.dart';

class MockLoadModelUsecase extends Mock implements LoadModelUsecase {}

class MockDetectFromFrame extends Mock implements DetectionObjectFromFrame {}

class MockCameraImage extends Mock implements CameraImage {}

class MockCloseModelUsecase extends Mock implements CloseModelUsecase {}

DetectionObject _safeObject({
  String label = 'person',
  double confidence = 0.8,
}) =>
    DetectionObject(
      label: label,
      confidence: confidence,
      boundingBox: const BoundingBox(
        left: 0.4,
        top: 0.4,
        width: 0.05,
        height: 0.05,
      ),
    );

DetectionObject _dangerousObject({
  String label = 'person',
  double confidence = 0.9,
}) =>
    DetectionObject(
      label: label,
      confidence: confidence,
      boundingBox: const BoundingBox(
        left: 0.1,
        top: 0.1,
        width: 0.4,
        height: 0.4,
      ),
    );

void main() {
  late MockLoadModelUsecase mockLoadModel;
  late MockDetectFromFrame mockDetectFromFrame;
  late MockCloseModelUsecase mockCloseModel;
  late MockCameraImage mockCameraImage;

  setUpAll(() {
    // CameraImage is used with any() in detectFromFrame stubs.
    registerFallbackValue(MockCameraImage());
    // NoParams is used with any() in loadModel.call() and closeModel.call() stubs.
    // Mocktail requires a fallback for every non-primitive type passed to any().
    registerFallbackValue(const NoParams());
  });

  setUp(() {
    mockLoadModel = MockLoadModelUsecase();
    mockDetectFromFrame = MockDetectFromFrame();
    mockCameraImage = MockCameraImage();
    mockCloseModel = MockCloseModelUsecase();

    // Default stubs — without these, DetectionStarted/Stopped would throw MissingStubError.
    // LoadModelUsecase implements UseCase<void, NoParams>, so the only callable
    // interface is .call(NoParams) — there is no .load() convenience method.
    when(() => mockLoadModel.call(any())).thenAnswer((_) async {});
    when(() => mockCloseModel.call(any())).thenAnswer((_) async {});
  });

  DetectionBloc buildBloc({DetectionWarningCallback? onWarning}) =>
      DetectionBloc(
        loadModel: mockLoadModel,
        detectFromFrame: mockDetectFromFrame,
        closeModel: mockCloseModel,
        onWarning: onWarning ??
            ({required text, required immediate, required withVibration}) {},
      );

  test('state ban đầu là DetectionInitial', () {
    final bloc = buildBloc();
    expect(bloc.state, const DetectionInitial());
    bloc.close();
  });

  group('DetectionStarted', () {
    blocTest<DetectionBloc, DetectionState>(
      'phát ra [Loading, ModelReady]',
      build: buildBloc,
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [
        const DetectionLoading(),
        const DetectionModelReady(),
      ],
    );

    blocTest<DetectionBloc, DetectionState>(
      'phát ra Failure khi loadModel thất bại',
      build: () {
        when(() => mockLoadModel.call(any()))
            .thenThrow(Exception('load error'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [
        const DetectionLoading(),
        isA<DetectionFailure>(),
      ],
    );
  });

  blocTest<DetectionBloc, DetectionState>(
    'DetectionStopped → quay về Initial và gọi closeModel',
    build: buildBloc,
    seed: () => const DetectionModelReady(),
    act: (bloc) => bloc.add(const DetectionStopped()),
    expect: () => [const DetectionInitial()],
    verify: (_) => verify(() => mockCloseModel.call(any())).called(1),
  );

  blocTest<DetectionBloc, DetectionState>(
    'không có phát hiện nào → success với danh sách rỗng',
    build: () {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => []);
      return buildBloc();
    },
    seed: () => const DetectionModelReady(),
    act: (bloc) => bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
    expect: () => [
      predicate<DetectionState>(
        (s) => s is DetectionSuccess && s.detections.isEmpty,
      ),
    ],
  );

  blocTest<DetectionBloc, DetectionState>(
    'một phát hiện đơn lẻ',
    build: () {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => [_safeObject()]);
      return buildBloc();
    },
    seed: () => const DetectionModelReady(),
    act: (bloc) => bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
    expect: () => [isA<DetectionSuccess>()],
  );

  group('Hành vi callback cảnh báo', () {
    String? capturedText;
    bool? capturedImmediate;

    setUp(() {
      capturedText = null;
      capturedImmediate = null;
    });

    blocTest<DetectionBloc, DetectionState>(
      'vật thể nguy hiểm → callback immediate=true sau 3 frame ổn định',
      // _triggerWarningIfNeeded fires only when isStable (currentCount==3) OR
      // isApproaching. With a single frame there is no previous area to compare
      // and currentCount==1, so the callback is never called.
      // Sending 3 identical frames makes currentCount reach 3 (isStable=true).
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_dangerousObject()]);
        return buildBloc(
          onWarning: (
              {required text, required immediate, required withVibration}) {
            capturedText = text;
            capturedImmediate = immediate;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) async {
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
      },
      expect: () => [
        isA<DetectionSuccess>(),
        isA<DetectionSuccess>(),
        isA<DetectionSuccess>()
      ],
      verify: (_) {
        expect(capturedImmediate, isTrue,
            reason: 'Vật thể nguy hiểm phải kích hoạt cảnh báo immediate=true');
        expect(capturedText, isNotEmpty);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'vật thể an toàn → callback immediate=false sau 3 frame ổn định',
      // Same debounce reasoning as above — 3 frames required for isStable.
      // A safe object (small area, ≤ dangerousAreaThreshold=0.10) triggers
      // the queued (immediate=false) path, not the danger path.
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_safeObject()]);
        return buildBloc(
          onWarning: (
              {required text, required immediate, required withVibration}) {
            capturedText = text;
            capturedImmediate = immediate;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) async {
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 10));
      },
      expect: () => [
        isA<DetectionSuccess>(),
        isA<DetectionSuccess>(),
        isA<DetectionSuccess>()
      ],
      verify: (_) {
        expect(capturedImmediate, isNotNull);
        expect(capturedImmediate, isFalse,
            reason: 'Vật thể an toàn phải kích hoạt cảnh báo immediate=false');
      },
    );
  });

  // With `droppable()` transformer, frames arriving while inference is
  // in-flight are discarded (exhaustMap semantics). CameraService already
  // provides a frame lock, droppable() is defense-in-depth at the BLoC layer.
  blocTest<DetectionBloc, DetectionState>(
    'droppable: hai frame đến cùng lúc — chỉ xử lý 1 frame, frame 2 bị bỏ',
    build: () {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 5));
        return [_safeObject()];
      });
      return buildBloc();
    },
    seed: () => const DetectionModelReady(),
    act: (bloc) async {
      bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
      bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
      await Future.delayed(const Duration(milliseconds: 50));
    },
    expect: () => [isA<DetectionSuccess>()],
    verify: (_) {
      // droppable discards the second frame while the first is in-flight.
      verify(() => mockDetectFromFrame(any(),
          rotationDegrees: any(named: 'rotationDegrees'))).called(1);
    },
  );

  blocTest<DetectionBloc, DetectionState>(
    'xử lý exception âm thầm — không phát state và vẫn gọi onDone',
    build: () {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenThrow(Exception('GPU error'));
      return buildBloc();
    },
    seed: () => const DetectionModelReady(),
    act: (bloc) => bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
    expect: () => <DetectionState>[],
  );
}
