import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detection_object.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/usecases/load_model_usecase.dart';
import '../../domain/usecases/close_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import '../../../../core/utils/perf_monitor.dart';
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

  Map<String, List<double>> _previousObjects = {};
  Map<String, int> _consecutiveFrames = {};
  final List<DetectionObject> _sortBuffer = [];

  Future<void>? _closeFuture;

  DetectionBloc({
    required LoadModelUsecase loadModel,
    required CloseModelUsecase closeModel,
    required DetectionObjectFromFrame detectFromFrame,
    required DetectionWarningCallback onWarning,
  })  : _loadModel = loadModel,
        _closeModel = closeModel,
        _detectFromFrame = detectFromFrame,
        _onWarning = onWarning,
        super(const DetectionInitial()) {
    on<DetectionStarted>(_onStarted);
    on<DetectionStopped>(_onStopped);
    // droppable() is correct here: with the latest-frame strategy,
    // CameraService only dispatches one frame at a time. droppable() acts as
    // a safety net for any edge case where two events arrive simultaneously.
    // The Future.microtask in _handleInferenceDone ensures the next event
    // arrives AFTER this handler is done, so it is never falsely dropped.
    on<DetectionFrameReceived>(_onFrameReceived, transformer: droppable());
  }

  Future<void> _onStarted(
    DetectionStarted event,
    Emitter<DetectionState> emit,
  ) async {
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
    if (kDebugMode) debugPrint('[DetectionBloc] loading model...');
    emit(const DetectionLoading());
    try {
      await _loadModel.call(const NoParams());
      if (kDebugMode) debugPrint('[DetectionBloc] model loaded');
      emit(const DetectionModelReady());
    } catch (e) {
      debugPrint('[DetectionBloc] model load FAILED: $e');
      emit(DetectionFailure(e.toString()));
    }
  }

  Future<void> _onStopped(
    DetectionStopped event,
    Emitter<DetectionState> emit,
  ) async {
    _resetWarningState();
    emit(const DetectionInitial());
    _closeFuture = _closeModel.call(const NoParams());
    try {
      await _closeFuture;
    } catch (e) {
      debugPrint('[DetectionBloc] closeModel error: $e');
    } finally {
      _closeFuture = null;
    }
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    // Skip frames that arrive before the model is ready.
    if (state is DetectionInitial ||
        state is DetectionLoading ||
        state is DetectionFailure) {
      if (kDebugMode) {
        debugPrint('[DetectionBloc] frame skipped — model not ready '
            '(${state.runtimeType})');
      }
      // MUST call onDone() to release CameraService._isProcessingFrame.
      // Without this, the camera stream locks up permanently.
      event.onDone();
      return;
    }

    final sw = kDebugMode ? (Stopwatch()..start()) : null;

    try {
      final detections = await _detectFromFrame(
        event.frame,
        rotationDegrees: event.rotationDegrees,
      );

      if (kDebugMode) {
        sw?.stop();
        PerfMonitor.inferenceCompleted(sw?.elapsedMilliseconds ?? 0);
        if (detections.isNotEmpty) {
          debugPrint('[DetectionBloc] detections=${detections.length} '
              'in ${sw?.elapsedMilliseconds}ms');
        }
      }

      emit(DetectionSuccess(
        detections: detections,
        timestamp: DateTime.now().microsecondsSinceEpoch,
      ));

      _triggerWarningIfNeeded(detections);
    } catch (e) {
      debugPrint('[DetectionBloc] _onFrameReceived error: $e');
    } finally {
      // INVARIANT: onDone() MUST be called even on exception.
      // CameraService._handleInferenceDone() will then schedule the next
      // pending frame via Future.microtask(). The microtask runs after
      // this finally block returns, ensuring droppable() sees this event
      // as complete before the next one is added.
      event.onDone();
    }
  }

  void _triggerWarningIfNeeded(List<DetectionObject> detections) {
    final currentObjects = _groupAreasByLabel(detections);
    final candidates = <DetectionObject>[];

    if (detections.isNotEmpty) {
      _sortBuffer
        ..clear()
        ..addAll(detections)
        ..sort((a, b) {
          final c = a.label.compareTo(b.label);
          if (c != 0) return c;
          return b.boundingBox.area.compareTo(a.boundingBox.area);
        });

      final currentIndices = <String, int>{};
      final newConsecutive = <String, int>{};

      for (final d in _sortBuffer) {
        final idx =
            currentIndices.update(d.label, (v) => v + 1, ifAbsent: () => 0);
        final key = '${d.label}_$idx';
        final count = (_consecutiveFrames[key] ?? 0) + 1;
        newConsecutive[key] = count;

        final prevAreas = _previousObjects[d.label];
        final oldArea =
            prevAreas != null && idx < prevAreas.length ? prevAreas[idx] : null;

        if ((oldArea != null && d.boundingBox.area > oldArea * 1.3) ||
            count == 3 ||
            count == 1) {
          candidates.add(d);
        }
      }
      _consecutiveFrames = newConsecutive;
    } else {
      _consecutiveFrames = {};
    }

    _previousObjects = currentObjects;
    if (candidates.isEmpty) return;

    final dangerous = candidates.where((d) => d.isDangerous).toList()
      ..sort((a, b) => b.boundingBox.area.compareTo(a.boundingBox.area));

    if (dangerous.isNotEmpty) {
      _onWarning(
        text: dangerous.first.voiceWarning,
        immediate: true,
        withVibration: true,
      );
    } else {
      final top =
          candidates.reduce((a, b) => a.confidence > b.confidence ? a : b);
      _onWarning(
        text: top.voiceWarning,
        immediate: false,
        withVibration: false,
      );
    }
  }

  Map<String, List<double>> _groupAreasByLabel(
      List<DetectionObject> detections) {
    final grouped = <String, List<double>>{};
    for (final d in detections) {
      grouped.putIfAbsent(d.label, () => []).add(d.boundingBox.area);
    }
    for (final areas in grouped.values) {
      areas.sort((a, b) => b.compareTo(a));
    }
    return grouped;
  }

  void _resetWarningState() {
    _previousObjects = {};
    _consecutiveFrames = {};
    _sortBuffer.clear();
  }

  @override
  Future<void> close() async {
    _sortBuffer.clear();
    if (_closeFuture != null) {
      try {
        await _closeFuture;
      } catch (_) {}
    }
    return super.close();
  }
}
