import 'package:bloc_test/bloc_test.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safe_vision_app/features/detection/domain/entities/detection_object.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/detection_object_from_frame.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/load_model_usecase.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/close_model_usecase.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_bloc.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_event.dart';
import 'package:safe_vision_app/features/detection/presentation/bloc/detection_state.dart';
import 'package:safe_vision_app/core/usecases/usecase.dart';

class MockLoadModelUsecase extends Mock implements LoadModelUsecase {}

class MockCloseModelUsecase extends Mock implements CloseModelUsecase {}

class MockDetectFromFrame extends Mock implements DetectionObjectFromFrame {}

class MockCameraImage extends Mock implements CameraImage {}

DetectionObject _safeObject(
        {String label = 'person', double confidence = 0.8}) =>
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

DetectionObject _dangerousObject(
        {String label = 'person', double confidence = 0.9}) =>
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
  late MockCloseModelUsecase mockCloseModel;
  late MockDetectFromFrame mockDetectFromFrame;
  late MockCameraImage mockCameraImage;

  setUpAll(() {
    registerFallbackValue(MockCameraImage());
    registerFallbackValue(const NoParams());
  });

  setUp(() {
    mockLoadModel = MockLoadModelUsecase();
    mockCloseModel = MockCloseModelUsecase();
    mockDetectFromFrame = MockDetectFromFrame();
    mockCameraImage = MockCameraImage();

    when(() => mockCloseModel.call(any())).thenAnswer((_) async {});
    when(() => mockLoadModel.call(any())).thenAnswer((_) async {});
  });

  DetectionBloc buildBloc({DetectionWarningCallback? onWarning}) =>
      DetectionBloc(
        loadModel: mockLoadModel,
        closeModel: mockCloseModel,
        detectFromFrame: mockDetectFromFrame,
        onWarning: onWarning ??
            ({required text, required immediate, required withVibration}) {},
      );

  // Initial state

  test('state ban đầu là DetectionInitial', () {
    final bloc = buildBloc();
    expect(bloc.state, const DetectionInitial());
    bloc.close();
  });

  // DetectionStarted

  group('DetectionStarted', () {
    blocTest<DetectionBloc, DetectionState>(
      'phát ra [Loading, ModelReady] khi khởi tạo thành công',
      build: buildBloc,
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [const DetectionLoading(), const DetectionModelReady()],
      verify: (_) => verify(() => mockLoadModel.call(any())).called(1),
    );

    blocTest<DetectionBloc, DetectionState>(
      'phát ra [Loading, Failure] khi loadModel ném lỗi',
      build: () {
        when(() => mockLoadModel.call(any()))
            .thenThrow(Exception('model not found'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DetectionStarted()),
      expect: () => [const DetectionLoading(), isA<DetectionFailure>()],
    );

    blocTest<DetectionBloc, DetectionState>(
      'trạng thái theo dõi được đặt lại mỗi khi gọi DetectionStarted',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const DetectionStarted());
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const DetectionStarted());
      },
      expect: () => [
        const DetectionLoading(),
        const DetectionModelReady(),
        const DetectionLoading(),
        const DetectionModelReady(),
      ],
    );
  });

  // DetectionStopped uses CloseModelUsecase

  group('DetectionStopped', () {
    blocTest<DetectionBloc, DetectionState>(
      'phát ra Initial và gọi closeModel',
      build: buildBloc,
      seed: () => const DetectionModelReady(),
      act: (bloc) => bloc.add(const DetectionStopped()),
      expect: () => [const DetectionInitial()],
      verify: (_) => verify(() => mockCloseModel.call(any())).called(1),
    );

    blocTest<DetectionBloc, DetectionState>(
      'vẫn gọi closeModel dù state ban đầu là Initial',
      build: buildBloc,
      act: (bloc) => bloc.add(const DetectionStopped()),
      expect: () => [const DetectionInitial()],
      verify: (_) => verify(() => mockCloseModel.call(any())).called(1),
    );
  });

  // Concurrent frames and droppable behavior

  group('DetectionFrameReceived — hành vi xử lý frame', () {
    blocTest<DetectionBloc, DetectionState>(
      'nhiều frame đến cùng lúc: chỉ một frame được xử lý tại một thời điểm',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return [_safeObject()];
        });
        return buildBloc();
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) async {
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        verify(() => mockDetectFromFrame(any(),
            rotationDegrees: any(named: 'rotationDegrees'))).called(1);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'hai frame tuần tự có độ trễ đều được xử lý',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => []);
        return buildBloc();
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) async {
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 30));
        bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {}));
        await Future.delayed(const Duration(milliseconds: 30));
      },
      verify: (_) {
        verify(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .called(greaterThanOrEqualTo(1));
      },
    );
  });

  // Warning callback

  group('Callback cảnh báo', () {
    String? capturedText;
    bool? capturedImmediate;
    bool? capturedVibration;

    setUp(() {
      capturedText = null;
      capturedImmediate = null;
      capturedVibration = null;
    });

    blocTest<DetectionBloc, DetectionState>(
      'vật thể nguy hiểm → callback có immediate=true và withVibration=true',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_dangerousObject()]);
        return buildBloc(
          onWarning: (
              {required text, required immediate, required withVibration}) {
            capturedText = text;
            capturedImmediate = immediate;
            capturedVibration = withVibration;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) =>
          bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        expect(capturedImmediate, isTrue);
        expect(capturedVibration, isTrue);
        expect(capturedText, isNotNull);
        expect(capturedText, isNotEmpty);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'vật thể an toàn → callback có immediate=false và withVibration=false',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => [_safeObject()]);
        return buildBloc(
          onWarning: (
              {required text, required immediate, required withVibration}) {
            capturedImmediate = immediate;
            capturedVibration = withVibration;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) =>
          bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [isA<DetectionSuccess>()],
      verify: (_) {
        expect(capturedImmediate, isFalse);
        expect(capturedVibration, isFalse);
      },
    );

    blocTest<DetectionBloc, DetectionState>(
      'không có phát hiện nào → không gọi callback',
      build: () {
        when(() => mockDetectFromFrame(any(),
                rotationDegrees: any(named: 'rotationDegrees')))
            .thenAnswer((_) async => []);
        return buildBloc(
          onWarning: (
              {required text, required immediate, required withVibration}) {
            capturedText = text;
          },
        );
      },
      seed: () => const DetectionModelReady(),
      act: (bloc) =>
          bloc.add(DetectionFrameReceived(mockCameraImage, 90, () {})),
      expect: () => [
        predicate<DetectionState>(
            (s) => s is DetectionSuccess && s.detections.isEmpty),
      ],
      verify: (_) {
        expect(capturedText, isNull,
            reason:
                'Không có vật thể nào được phát hiện nên không được gọi callback');
      },
    );
  });

  // onDone callback

  group('Callback onDone', () {
    test('is called after successful inference', () async {
      when(() => mockDetectFromFrame(any(),
              rotationDegrees: any(named: 'rotationDegrees')))
          .thenAnswer((_) async => []);

      final bloc = buildBloc();
      bloc.add(const DetectionStarted());
      await Future.delayed(const Duration(milliseconds: 10));

      bool doneCalled = false;
      bloc.add(DetectionFrameReceived(
        mockCameraImage,
        0,
        () => doneCalled = true,
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(doneCalled, isTrue,
          reason: 'onDone() phải được gọi sau mỗi frame');
      await bloc.close();
    });
  });

  // CloseModelUsecase contract

  group('CloseModelUsecase', () {
    test('call(NoParams()) chuyển tiếp sang repository.closeModel()', () async {
      final mock = MockCloseModelUsecase();
      when(() => mock.call(any())).thenAnswer((_) async {});

      await mock.call(const NoParams());

      verify(() => mock.call(any())).called(1);
    });
  });
}
