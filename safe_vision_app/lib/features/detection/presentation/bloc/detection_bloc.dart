import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/services/warning_dispatcher.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/perf_monitor.dart';
import '../../domain/entities/tracked_detection.dart';
import '../../domain/services/object_tracker.dart';
import '../../domain/services/warning_policy.dart';
import '../../domain/usecases/close_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import '../../domain/usecases/load_model_usecase.dart';
import 'detection_event.dart';
import 'detection_state.dart';

typedef DetectionWarningCallback = void Function({
  required String text,
  required bool immediate,
  required bool withVibration,
});

class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final LoadModelUsecase _loadModel;
  final CloseModelUsecase _closeModel;
  final DetectionObjectFromFrame _detectFromFrame;
  final DetectionWarningCallback _onWarning;
  final ObjectTracker _objectTracker;
  final WarningPolicy _warningPolicy;

  Future<void>? _closeFuture;
  Future<void> _lifecycleChain = Future<void>.value();
  bool _modelReady = false;
  bool _isShuttingDown = false;
  int _pipelineGeneration = 0;

  DetectionBloc({
    required LoadModelUsecase loadModel,
    required CloseModelUsecase closeModel,
    required DetectionObjectFromFrame detectFromFrame,
    DetectionWarningCallback? onWarning,
    WarningDispatcher? warningDispatcher,
    ObjectTracker? objectTracker,
    WarningPolicy? warningPolicy,
  })  : _loadModel = loadModel,
        _closeModel = closeModel,
        _detectFromFrame = detectFromFrame,
        _onWarning =
            onWarning ?? _warningCallbackFromDispatcher(warningDispatcher),
        _objectTracker = objectTracker ?? ObjectTracker(),
        _warningPolicy = warningPolicy ?? WarningPolicy(),
        super(const DetectionInitial()) {
    on<DetectionStarted>(_onStarted);
    on<DetectionStopped>(_onStopped);
    on<DetectionFrameReceived>(_onFrameReceived, transformer: droppable());
  }

  static DetectionWarningCallback _warningCallbackFromDispatcher(
    WarningDispatcher? warningDispatcher,
  ) {
    if (warningDispatcher == null) {
      throw ArgumentError(
        'Either onWarning or warningDispatcher must be provided.',
      );
    }
    return ({
      required String text,
      required bool immediate,
      required bool withVibration,
    }) {
      warningDispatcher.dispatch(
        text: text,
        immediate: immediate,
        withVibration: withVibration,
      );
    };
  }

  Future<void> _onStarted(
    DetectionStarted event,
    Emitter<DetectionState> emit,
  ) {
    return _runLifecycleTask(() async {
      _pipelineGeneration++;
      final generation = _pipelineGeneration;

      if (_closeFuture != null) {
        try {
          await _closeFuture;
        } catch (e) {
          debugPrint('[DetectionBloc] _closeFuture threw on restart: $e');
        } finally {
          _closeFuture = null;
        }
      }

      _resetWarningState();
      _objectTracker.clear();
      _modelReady = false;
      if (kDebugMode) debugPrint('[DetectionBloc] loading model...');
      emit(const DetectionLoading());
      try {
        await _loadModel.call(const NoParams());
        if (_isShuttingDown || generation != _pipelineGeneration || isClosed) {
          _closeFuture ??= _closeModel.call(const NoParams());
          await _closeFuture;
          _closeFuture = null;
          return;
        }
        _modelReady = true;
        if (kDebugMode) debugPrint('[DetectionBloc] model loaded');
        emit(const DetectionModelReady());
      } catch (e) {
        _modelReady = false;
        debugPrint('[DetectionBloc] model load FAILED: $e');
        emit(DetectionFailure(e.toString()));
      }
    });
  }

  Future<void> _onStopped(
    DetectionStopped event,
    Emitter<DetectionState> emit,
  ) {
    return _runLifecycleTask(() async {
      _pipelineGeneration++;
      _modelReady = false;
      _resetWarningState();
      _objectTracker.clear();
      emit(const DetectionInitial());
      _closeFuture = _closeModel.call(const NoParams());
      try {
        await _closeFuture;
      } catch (e) {
        debugPrint('[DetectionBloc] closeModel error: $e');
      } finally {
        _closeFuture = null;
      }
    });
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    if (!_canProcessFrames) {
      if (kDebugMode) {
        debugPrint(
          '[DetectionBloc] frame skipped - model not ready (${state.runtimeType})',
        );
      }
      event.onDone();
      return;
    }

    final generation = _pipelineGeneration;
    final sw = kDebugMode ? (Stopwatch()..start()) : null;

    try {
      final detections = await _detectFromFrame(
        event.frame,
        rotationDegrees: event.rotationDegrees,
      );
      if (_isShuttingDown ||
          generation != _pipelineGeneration ||
          !_canProcessFrames ||
          isClosed ||
          state is DetectionInitial ||
          state is DetectionLoading) {
        return;
      }

      final trackedDetections = _objectTracker.update(detections);

      if (kDebugMode) {
        sw?.stop();
        PerfMonitor.inferenceCompleted(sw?.elapsedMilliseconds ?? 0);
        if (detections.isNotEmpty) {
          debugPrint(
            '[DetectionBloc] detections=${detections.length} in ${sw?.elapsedMilliseconds}ms',
          );
        }
      }

      emit(
        DetectionSuccess(
          detections: detections,
          trackedDetections: trackedDetections,
          timestamp: DateTime.now().microsecondsSinceEpoch,
        ),
      );

      _triggerWarningIfNeeded(trackedDetections);
    } on InferenceException catch (e) {
      _objectTracker.clear();
      _resetWarningState();
      debugPrint('[DetectionBloc] InferenceException: $e');
    } catch (e) {
      _objectTracker.clear();
      _resetWarningState();
      debugPrint('[DetectionBloc] _onFrameReceived error: $e');
    } finally {
      event.onDone();
    }
  }

  void _triggerWarningIfNeeded(List<TrackedDetection> trackedDetections) {
    final action = _warningPolicy.evaluate(trackedDetections);
    if (action == null) return;

    _onWarning(
      text: action.text,
      immediate: action.immediate,
      withVibration: action.withVibration,
    );
  }

  void _resetWarningState() {
    _warningPolicy.reset();
  }

  bool get _canProcessFrames =>
      _modelReady || state is DetectionModelReady || state is DetectionSuccess;

  Future<void> _runLifecycleTask(Future<void> Function() task) {
    final completer = Completer<void>();
    _lifecycleChain = _lifecycleChain.catchError((_) {}).then((_) async {
      try {
        await task();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<void> close() async {
    _isShuttingDown = true;
    _pipelineGeneration++;
    _objectTracker.clear();
    _resetWarningState();
    await _lifecycleChain.catchError((_) {});

    if (_closeFuture != null) {
      try {
        await _closeFuture;
      } catch (_) {}
    } else if (_modelReady || state is! DetectionInitial) {
      try {
        await _closeModel.call(const NoParams());
      } catch (_) {}
    }

    _modelReady = false;
    return super.close();
  }
}
